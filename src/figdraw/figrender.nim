import std/[hashes, math, tables, unicode]
export tables

from pkg/pixie import Image, newImage, flipVertical
import pkg/chroma
import pkg/chronicles

import ./commons
import ./utils/drawshadows
import ./utils/drawboxes
import ./common/fontglyphs

import ./opengl/glcommons

when UseMetalBackend:
  import ./metal/metal_context
  import metalx/metal
else:
  import pkg/opengl
  import ./utils/glutils
  import ./opengl/glcontext
  export glutils

const FastShadows {.booldefine: "figuro.fastShadows".}: bool = false

type FigRenderer* = ref object
  ctx*: Context

when UseMetalBackend:
  proc metalDevice*(ctx: Context): MTLDevice =
    ## Convenience re-export so callers using `figdraw/figrender` don't also
    ## need to import `figdraw/metal/glcontext_metal`.
    metal_context.metalDevice(ctx)

proc takeScreenshot*(
    renderer: FigRenderer, frame: Rect = rect(0, 0, 0, 0), readFront: bool = true
): Image =
  discard readFront
  let ctx: Context = renderer.ctx
  when UseMetalBackend:
    result = ctx.readPixels(frame)
  else:
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

proc newFigRenderer*(atlasSize: int, pixelScale = app.pixelScale): FigRenderer =
  result = FigRenderer()
  when UseMetalBackend:
    result.ctx =
      newContext(atlasSize = atlasSize, pixelate = false, pixelScale = pixelScale)
  else:
    result.ctx =
      newContext(atlasSize = atlasSize, pixelate = false, pixelScale = pixelScale)

proc newFigRenderer*(ctx: Context): FigRenderer =
  ## Uses a caller-created backend context.
  result = FigRenderer(ctx: ctx)

proc renderDrawable*(ctx: Context, node: Fig) =
  ## TODO: draw non-node stuff?
  let box = node.screenBox.scaled()
  for point in node.points:
    let
      pos = point.scaled()
      bx = box.atXY(pos.x, pos.y)
    ctx.drawRect(bx, node.fill)

proc renderText(ctx: Context, node: Fig) {.forbids: [AppMainThreadEff].} =
  ## Draw characters (glyphs)
  for glyph in node.textLayout.glyphs():
    if unicode.isWhiteSpace(glyph.rune):
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

proc scaledCorners(
    corners: array[DirectionCorners, float32]
): array[DirectionCorners, float32] =
  for corner in DirectionCorners:
    result[corner] = corners[corner].scaled()

proc drawMasks(ctx: Context, node: Fig) =
  ctx.drawRoundedRectSdf(
    rect = node.screenBox.scaled(),
    color = rgba(255, 0, 0, 255).color,
    radii = node.corners.scaledCorners(),
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
        box = node.screenBox.scaled()
        shadowX = shadow.x.scaled()
        shadowY = shadow.y.scaled()
        shadowBlur = shadow.blur.scaled()
        shadowSpread = shadow.spread.scaled()
        blurPad = round(1.5'f32 * shadowBlur)
        pad = max(shadowSpread.round() + blurPad, 0.0'f32)
        shadowRect = box + rect(shadowX, shadowY, 0, 0)
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
        radii = node.corners.scaledCorners(),
        mode = sdfModeDropShadow,
        factor = shadowBlur,
        spread = shadowSpread,
      )
    elif FastShadows:
      ## should add a primitive to opengl.context to
      var color = shadow.color
      const N = 3
      color.a = color.a * 1.0 / (N * N * N)
      let blurAmt = shadow.blur.scaled() * shadow.spread.scaled() / (12 * N * N)
      for i in -N .. N:
        for j in -N .. N:
          let xblur: float32 = i.toFloat() * blurAmt
          let yblur: float32 = j.toFloat() * blurAmt
          let box = node.screenBox.scaled().atXY(
              x = shadow.x.scaled() + xblur, y = shadow.y.scaled() + yblur
            )
          ctx.drawRoundedRect(
            rect = box, color = color, radius = node.corners.scaledCorners()
          )
    else:
      ctx.fillRoundedRectWithShadowSdf(
        rect = node.screenBox.scaled(),
        radii = node.corners.scaledCorners(),
        shadowX = shadow.x.scaled(),
        shadowY = shadow.y.scaled(),
        shadowBlur = shadow.blur.scaled(),
        shadowSpread = shadow.spread.scaled(),
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
      let shadowRect =
        node.screenBox.scaled() + rect(shadow.x.scaled(), shadow.y.scaled(), 0, 0)
      ctx.drawRoundedRectSdf(
        rect = shadowRect,
        shapeSize = shadowRect.wh,
        color = shadow.color,
        radii = node.corners.scaledCorners(),
        mode = sdfModeInsetShadowAnnular,
        factor = shadow.blur.scaled(),
        spread = shadow.spread.scaled(),
      )
    elif FastShadows:
      ## this is even more incorrect than drop shadows, but it's something
      ## and I don't actually want to think today ;)
      let n = shadow.blur.scaled().toInt
      var color = shadow.color
      color.a = 2 * color.a / n.toFloat
      let blurAmt = shadow.blur.scaled() / n.toFloat
      for i in 0 .. n:
        let blur: float32 = i.toFloat() * blurAmt
        var box = node.screenBox.scaled()
        if shadow.x >= 0'f32:
          box.w += shadow.x.scaled()
        else:
          box.x += shadow.x.scaled() + blurAmt
        if shadow.y >= 0'f32:
          box.h += shadow.y.scaled()
        else:
          box.y += shadow.y.scaled() + blurAmt
        ctx.strokeRoundedRect(
          rect = box,
          color = color,
          weight = blur,
          radius = node.corners.scaledCorners() - blur,
        )
    else:
      ctx.fillRoundedRectWithShadowSdf(
        rect = node.screenBox.scaled(),
        radii = node.corners.scaledCorners(),
        shadowX = shadow.x.scaled(),
        shadowY = shadow.y.scaled(),
        shadowBlur = shadow.blur.scaled(),
        shadowSpread = shadow.spread.scaled(),
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

  let
    box = node.screenBox.scaled()
    corners = node.corners.scaledCorners()

  if node.fill.a > 0'f32:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(rect = box, color = node.fill, radii = corners)
    else:
      if node.corners != [0'f32, 0'f32, 0'f32, 0'f32]:
        ctx.drawRoundedRect(rect = box, color = node.fill, radii = corners)
      else:
        ctx.drawRect(box, node.fill)

  if node.stroke.color.a > 0 and node.stroke.weight > 0:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = box,
        color = node.stroke.color,
        radii = corners,
        mode = sdfModeAnnularAA,
        factor = node.stroke.weight.scaled(),
      )
    else:
      ctx.drawRoundedRect(
        rect = box,
        color = node.stroke.color,
        radii = corners,
        weight = node.stroke.weight.scaled(),
        doStroke = true,
      )

proc renderImage(ctx: Context, node: Fig) =
  if node.image.id.int == 0:
    return
  let box = node.screenBox.scaled()
  let size = vec2(box.w, box.h)
  ctx.drawImage(node.image.id.Hash, pos = box.xy, color = node.image.color, size = size)

proc renderMsdfImage(ctx: Context, node: Fig) =
  if node.msdfImage.id.int == 0:
    return
  let box = node.screenBox.scaled()
  let size = vec2(box.w, box.h)
  let pxRange =
    if node.msdfImage.pxRange > 0.0'f32: node.msdfImage.pxRange else: 4.0'f32
  let sdThreshold =
    if node.msdfImage.sdThreshold > 0.0'f32 and node.msdfImage.sdThreshold < 1.0'f32:
      node.msdfImage.sdThreshold
    else:
      0.5'f32
  ctx.drawMsdfImage(
    node.msdfImage.id.Hash,
    pos = box.xy,
    color = node.msdfImage.color,
    size = size,
    pxRange = pxRange,
    sdThreshold = sdThreshold,
  )

proc renderMtsdfImage(ctx: Context, node: Fig) =
  if node.mtsdfImage.id.int == 0:
    return
  let box = node.screenBox.scaled()
  let size = vec2(box.w, box.h)
  let pxRange =
    if node.mtsdfImage.pxRange > 0.0'f32: node.mtsdfImage.pxRange else: 4.0'f32
  let sdThreshold =
    if node.mtsdfImage.sdThreshold > 0.0'f32 and node.mtsdfImage.sdThreshold < 1.0'f32:
      node.mtsdfImage.sdThreshold
    else:
      0.5'f32
  ctx.drawMtsdfImage(
    node.mtsdfImage.id.Hash,
    pos = box.xy,
    color = node.mtsdfImage.color,
    size = size,
    pxRange = pxRange,
    sdThreshold = sdThreshold,
  )

proc render(
    ctx: Context, nodes: seq[Fig], nodeIdx, parentIdx: FigIdx
) {.forbids: [AppMainThreadEff].} =
  template node(): auto =
    nodes[nodeIdx.int]

  ## Draws the node.
  ##
  ## This is the primary routine that handles setting up the rendering
  ## context. This doesn't necessarily trigger the actual GPU rendering, but
  ## configures the various shaders and elements.
  if NfDisableRender in node.flags:
    return
  let box = node.screenBox.scaled()

  # handle node rotation
  ifrender node.rotation != 0:
    ctx.saveTransform()
    ctx.translate(box.xy + box.wh / 2)
    ctx.rotate(node.rotation / 180 * PI)
    ctx.translate(-(box.xy + box.wh / 2))
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
      ctx.translate(box.xy)
      ctx.renderText(node)
      ctx.restoreTransform()
    elif node.kind == nkDrawable:
      ctx.renderDrawable(node)
    elif node.kind == nkRectangle:
      ctx.renderBoxes(node)
    elif node.kind == nkImage:
      ctx.renderImage(node)
    elif node.kind == nkMsdfImage:
      ctx.renderMsdfImage(node)
    elif node.kind == nkMtsdfImage:
      ctx.renderMtsdfImage(node)

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

  for childIdx in childIndex(nodes, nodeIdx):
    ctx.render(nodes, childIdx, nodeIdx)

  postRender()

proc renderRoot*(ctx: Context, nodes: var Renders) {.forbids: [AppMainThreadEff].} =
  ## draw roots for each level
  var img: ImgObj
  while imageChan.tryRecv(img):
    debug "image loaded", id = $img.id.Hash
    ctx.putImage(img)

  for zlvl, list in nodes.layers.pairs():
    for rootIdx in list.rootIds:
      ctx.render(list.nodes, rootIdx, -1.FigIdx)

proc renderFrame*(
    renderer: FigRenderer,
    nodes: var Renders,
    frameSize: Vec2,
    clearMain: bool = true,
    clearColor: Color = color(1.0, 1.0, 1.0, 1.0),
) =
  let ctx: Context = renderer.ctx
  let frameSize = frameSize.scaled()
  when UseMetalBackend:
    ctx.beginFrame(frameSize, clearMain = clearMain, clearMainColor = clearColor)
  else:
    if clearMain:
      clearColorBuffer(clearColor)
    ctx.beginFrame(frameSize)

  ctx.saveTransform()
  ctx.scale(ctx.pixelScale)
  ctx.renderRoot(nodes)
  ctx.restoreTransform()
  ctx.endFrame()

  when defined(testOneFrame) and not UseMetalBackend:
    ## This is used for test only
    ## Take a screen shot of the first frame and exit.
    var img = takeScreenshot(renderer)
    img.writeFile("screenshot.png")
    quit()
