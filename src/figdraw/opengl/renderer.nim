import std/[hashes, math, tables, unicode]
export tables

from pixie import Image, newImage, flipVertical
import pkg/chroma
import pkg/chronicles
import pkg/opengl

import ../commons
import ../utils/glutils
import ../utils/drawshadows
import ../utils/drawboxes
import glcommons, glcontext

const FastShadows {.booldefine: "figuro.fastShadows".}: bool = false

type OpenGLRenderer* = ref object
  ctx*: Context

proc takeScreenshot*(frame: Rect = rect(0, 0, 0, 0),
    readFront: bool = true): Image =
  var viewport: array[4, GLint]
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)

  let
    viewportWidth = viewport[2].int
    viewportHeight = viewport[3].int

  var x = frame.x.int
  var y = frame.y.int
  var w = frame.w.int
  var h = frame.h.int

  if w <= 0 or h <= 0:
    x = 0
    y = 0
    w = viewportWidth
    h = viewportHeight

  glReadBuffer(if readFront: GL_FRONT else: GL_BACK)
  result = newImage(w, h)
  glReadPixels(
    x.GLint, y.GLint, w.GLint, h.GLint, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr
  )
  result.flipVertical()
  glReadBuffer(GL_BACK)

proc newOpenGLRenderer*(atlasSize: int, pixelScale = app.pixelScale): OpenGLRenderer =
  result = OpenGLRenderer()
  result.ctx =
    newContext(atlasSize = atlasSize, pixelate = false, pixelScale = pixelScale)

proc renderDrawable*(ctx: Context, node: Fig) =
  ## TODO: draw non-node stuff?
  for point in node.points:
    let
      pos = point
      bx = node.screenBox.atXY(pos.x, pos.y)
    ctx.drawRect(bx, node.fill)

proc renderText(ctx: Context, node: Fig) {.forbids: [AppMainThreadEff].} =
  ## draw characters (glyphs)

  for glyph in node.textLayout.glyphs():
    if unicode.isWhiteSpace(glyph.rune):
      # Don't draw space, even if font has a char for it.
      # FIXME: use unicode 'is whitespace' ?
      continue

    let
      glyphId = glyph.hash()
      charPos = vec2(glyph.pos.x, glyph.pos.y - glyph.descent * 1.0)
    if glyphId notin ctx.entries:
      trace "no glyph in context: ",
        glyphId = glyphId, glyph = glyph.rune, glyphRepr = repr(glyph.rune)
      continue
    ctx.drawImage(glyphId, charPos, node.fill)

import macros except `$`

var postRenderImpl {.compileTime.}: seq[NimNode]

macro ifrender(check, code: untyped, post: untyped = nil) =
  ## check if code should be drawn
  ##
  ## re-order code from:
  ## ifrender: a finally: a'
  ## ifrender: b finally: b'
  ## ifrender: c finally: c'
  ##
  ## to a pyramid form:
  ## a
  ##   b
  ##     c
  ##     c'
  ##   b'
  ## a'
  ##
  result = newStmtList()
  let checkval = genSym(nskLet, "checkval")
  result.add quote do:
    # currLevel and `check`
    let `checkval` = `check`
    if `checkval`:
      `code`

  if post != nil:
    post.expectKind(nnkFinally)
    let postBlock = post[0]
    postRenderImpl.add quote do:
      if `checkval`:
        `postBlock`

macro postRender() =
  result = newStmtList()
  while postRenderImpl.len() > 0:
    result.add postRenderImpl.pop()

proc drawMasks(ctx: Context, node: Fig) =
  ctx.drawRoundedRectSdf(
    rect = node.screenBox, color = rgba(255, 0, 0, 255).color,
        radii = node.corners
  )

proc renderDropShadows(ctx: Context, node: Fig) =
  ## drawing shadows with various techniques
  for shadow in node.shadows:
    if shadow.style != DropShadow:
      continue
    if shadow.blur <= 0.0 and shadow.spread <= 0.0:
      continue

    when not defined(useFigDrawTextures):
      let
        blurPad = round(1.5'f32 * shadow.blur)
        pad = max(shadow.spread.round() + blurPad, 0.0'f32)
        shadowRect = node.screenBox + rect(shadow.x, shadow.y, 0, 0)
        quadRect = rect(
          shadowRect.x - pad,
          shadowRect.y - pad,
          shadowRect.w + 2.0'f32 * pad,
          shadowRect.h + 2.0'f32 * pad,
        )
      ctx.drawRoundedRectSdf(
        rect = quadRect,
        shapeSize = shadowRect.wh,
        color = shadow.color,
        radii = node.corners,
        mode = sdfModeDropShadow,
        factor = shadow.blur,
        spread = shadow.spread,
      )
    elif FastShadows:
      ## should add a primitive to opengl.context to
      var color = shadow.color
      const N = 3
      color.a = color.a * 1.0 / (N * N * N)
      let blurAmt = shadow.blur * shadow.spread / (12 * N * N)
      for i in -N .. N:
        for j in -N .. N:
          let xblur: float32 = i.toFloat() * blurAmt
          let yblur: float32 = j.toFloat() * blurAmt
          let box = node.screenBox.atXY(x = shadow.x + xblur, y = shadow.y + yblur)
          ctx.drawRoundedRect(rect = box, color = color, radius = node.corners)
    else:
      ctx.fillRoundedRectWithShadowSdf(
        rect = node.screenBox,
        radii = node.corners,
        shadowX = shadow.x,
        shadowY = shadow.y,
        shadowBlur = shadow.blur,
        shadowSpread = shadow.spread.float32,
        shadowColor = shadow.color,
        innerShadow = false,
      )

proc renderInnerShadows(ctx: Context, node: Fig) =
  ## drawing inner shadows with various techniques
  for shadow in node.shadows:
    if shadow.style != InnerShadow:
      continue
    if shadow.blur <= 0.0 and shadow.spread <= 0.0:
      continue
    if shadow.color.a <= 0.0:
      continue

    when not defined(useFigDrawTextures):
      let shadowRect = node.screenBox + rect(shadow.x, shadow.y, 0, 0)
      ctx.drawRoundedRectSdf(
        rect = shadowRect,
        shapeSize = shadowRect.wh,
        color = shadow.color,
        radii = node.corners,
        mode = sdfModeInsetShadowAnnular,
        factor = shadow.blur,
        spread = shadow.spread,
      )
    elif FastShadows:
      ## this is even more incorrect than drop shadows, but it's something
      ## and I don't actually want to think today ;)
      let n = shadow.blur.toInt
      var color = shadow.color
      color.a = 2 * color.a / n.toFloat
      let blurAmt = shadow.blur / n.toFloat
      for i in 0 .. n:
        let blur: float32 = i.toFloat() * blurAmt
        var box = node.screenBox
        # var box = node.screenBox.atXY(x = shadow.x, y = shadow.y)
        if shadow.x >= 0'f32:
          box.w += shadow.x
        else:
          box.x += shadow.x + blurAmt
        if shadow.y >= 0'f32:
          box.h += shadow.y
        else:
          box.y += shadow.y + blurAmt
        ctx.strokeRoundedRect(
          rect = box, color = color, weight = blur, radius = node.corners - blur
        )
    else:
      ctx.fillRoundedRectWithShadowSdf(
        rect = node.screenBox,
        radii = node.corners,
        shadowX = shadow.x,
        shadowY = shadow.y,
        shadowBlur = shadow.blur,
        shadowSpread = shadow.spread.float32,
        shadowColor = shadow.color,
        innerShadow = true,
      )

proc hasActiveInnerShadow(node: Fig): bool =
  if node.shadows.len == 0:
    return false
  for shadow in node.shadows:
    if shadow.style != InnerShadow:
      continue
    if shadow.blur <= 0.0 and shadow.spread <= 0.0:
      continue
    if shadow.color.a <= 0.0:
      continue
    return true
  return false

proc renderBoxes(ctx: Context, node: Fig) =
  ## drawing boxes for rectangles

  if node.fill.a > 0'f32:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = node.screenBox, color = node.fill, radii = node.corners
      )
    else:
      if node.corners != [0'f32, 0'f32, 0'f32, 0'f32]:
        ctx.drawRoundedRect(
          rect = node.screenBox, color = node.fill, radii = node.corners
        )
      else:
        ctx.drawRect(node.screenBox, node.fill)

  if node.stroke.color.a > 0 and node.stroke.weight > 0:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = node.screenBox,
        color = node.stroke.color,
        radii = node.corners,
        mode = sdfModeAnnularAA,
        factor = node.stroke.weight,
      )
    else:
      ctx.drawRoundedRect(
        rect = node.screenBox,
        color = node.stroke.color,
        radii = node.corners,
        weight = node.stroke.weight,
        doStroke = true,
      )

proc renderImage(ctx: Context, node: Fig) =
  if node.image.id.int == 0:
    return
  let size = vec2(node.screenBox.w, node.screenBox.h)
  let pxRange = if node.image.msdfPxRange >
      0.0'f32: node.image.msdfPxRange else: 4.0'f32
  let sdThreshold =
    if node.image.msdfThreshold > 0.0'f32 and node.image.msdfThreshold < 1.0'f32:
      node.image.msdfThreshold
    else:
      0.5'f32
  case node.image.mode
  of irmBitmap:
    ctx.drawImage(
      node.image.id.Hash, pos = node.screenBox.xy, color = node.image.color, size = size
    )
  of irmMsdf:
    ctx.drawMsdfImage(
      node.image.id.Hash,
      pos = node.screenBox.xy,
      color = node.image.color,
      size = size,
      pxRange = pxRange,
      sdThreshold = sdThreshold,
    )
  of irmMtsdf:
    ctx.drawMtsdfImage(
      node.image.id.Hash,
      pos = node.screenBox.xy,
      color = node.image.color,
      size = size,
      pxRange = pxRange,
      sdThreshold = sdThreshold,
    )

proc render(
    ctx: Context, nodes: seq[Fig], nodeIdx, parentIdx: FigIdx
) {.forbids: [AppMainThreadEff].} =
  template node(): auto =
    nodes[nodeIdx.int]

  template parent(): auto =
    nodes[parentIdx.int]

  ## Draws the node.
  ##
  ## This is the primary routine that handles setting up the OpenGL
  ## context that will get rendered. This doesn't trigger the actual
  ## OpenGL rendering, but configures the various shaders and elements.
  ##
  ## Note that visiable draw calls need to check they're on the current
  ## active ZLevel (z-index).
  if NfDisableRender in node.flags:
    return

  # setup the opengl context to match the current node size and position

  # ctx.saveTransform()
  # ctx.translate(node.screenBox.xy)

  # handle node rotation
  ifrender node.rotation != 0:
    ctx.saveTransform()
    ctx.translate(node.screenBox.wh / 2)
    ctx.rotate(node.rotation / 180 * PI)
    ctx.translate(-node.screenBox.wh / 2)
  finally:
    ctx.restoreTransform()

  ifrender node.kind == nkRectangle:
    ctx.renderDropShadows(node)

  # handle clipping children content based on this node
  ifrender NfClipContent in node.flags:
    ctx.beginMask()
    ctx.drawMasks(node)
    ctx.endMask()
  finally:
    ctx.popMask()

  ifrender true:
    if node.kind == nkText:
      ctx.saveTransform()
      ctx.translate(node.screenBox.xy)
      ctx.renderText(node)
      ctx.restoreTransform()
    elif node.kind == nkDrawable:
      ctx.renderDrawable(node)
    elif node.kind == nkRectangle:
      ctx.renderBoxes(node)
    elif node.kind == nkImage:
      ctx.renderImage(node)

  ifrender node.kind == nkRectangle:
    when not defined(useFigDrawTextures):
      if node.hasActiveInnerShadow():
        ctx.renderInnerShadows(node)
    else:
      if NfClipContent notin node.flags:
        if node.hasActiveInnerShadow():
          ctx.beginMask()
          ctx.drawMasks(node)
          ctx.endMask()
          ctx.renderInnerShadows(node)
          ctx.popMask()
      else:
        ctx.renderInnerShadows(node)

  # restores the opengl context back to the parent node's (see above)
  # ctx.restoreTransform()

  for childIdx in childIndex(nodes, nodeIdx):
    ctx.render(nodes, childIdx, nodeIdx)

  # finally blocks will be run here, in reverse order
  postRender()

proc renderRoot*(ctx: Context, nodes: var Renders) {.forbids: [
    AppMainThreadEff].} =
  ## draw roots for each level
  var img: ImgObj
  while imageChan.tryRecv(img):
    debug "image loaded", id = $img.id.Hash
    ctx.putImage(img)

  for zlvl, list in nodes.layers.pairs():
    for rootIdx in list.rootIds:
      ctx.render(list.nodes, rootIdx, -1.FigIdx)

proc renderFrame*(renderer: OpenGLRenderer, nodes: var Renders,
    frameSize: Vec2) =
  let ctx: Context = renderer.ctx
  clearColorBuffer(color(1.0, 1.0, 1.0, 1.0))
  ctx.beginFrame(frameSize)
  ctx.saveTransform()
  ctx.scale(ctx.pixelScale)

  # draw root
  ctx.renderRoot(nodes)

  ctx.restoreTransform()
  ctx.endFrame()

  when defined(testOneFrame):
    ## This is used for test only
    ## Take a screen shot of the first frame and exit.
    var img = takeScreenshot()
    img.writeFile("screenshot.png")
    quit()

proc renderOverlayFrame*(
    renderer: OpenGLRenderer, nodes: var Renders, frameSize: Vec2
) =
  ## Render without clearing the color buffer (useful for UI overlays).
  let ctx: Context = renderer.ctx
  ctx.beginFrame(frameSize)
  ctx.saveTransform()
  ctx.scale(ctx.pixelScale)
  ctx.renderRoot(nodes)
  ctx.restoreTransform()
  ctx.endFrame()

proc renderFrame*(
    ctx: Context, nodes: var Renders, frameSize: Vec2,
        pixelScale = ctx.pixelScale
) =
  clearColorBuffer(color(1.0, 1.0, 1.0, 1.0))
  ctx.beginFrame(frameSize)
  ctx.saveTransform()
  ctx.scale(pixelScale)
  ctx.renderRoot(nodes)
  ctx.restoreTransform()
  ctx.endFrame()

proc renderOverlayFrame*(
    ctx: Context, nodes: var Renders, frameSize: Vec2,
        pixelScale = ctx.pixelScale
) =
  ## Render without clearing the color buffer (useful for UI overlays).
  ctx.beginFrame(frameSize)
  ctx.saveTransform()
  ctx.scale(pixelScale)
  ctx.renderRoot(nodes)
  ctx.restoreTransform()
  ctx.endFrame()
