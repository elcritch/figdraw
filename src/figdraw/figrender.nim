import std/[hashes, math, os, strutils, tables, unicode]
export tables

from pkg/pixie import Image
import pkg/chroma
import pkg/chronicles

import ./commons
import ./figbackend
import ./fignodes
import ./common/fontglyphs
export figbackend

when UseMetalBackend and UseOpenGlFallback:
  import ./metal/metal_context as preferred_backend
  import metalx/[metal, cametal]
  import pkg/opengl
  import ./utils/glutils
  import ./opengl/glcontext as opengl_context
  export glutils
elif UseVulkanBackend and UseOpenGlFallback:
  import ./vulkan/vulkan_context as preferred_backend
  import pkg/opengl
  import ./utils/glutils
  import ./opengl/glcontext as opengl_context
  export glutils
elif UseMetalBackend:
  import ./metal/metal_context
  import metalx/[metal, cametal]
elif UseVulkanBackend:
  import ./vulkan/vulkan_context
else:
  import pkg/opengl
  import ./utils/glutils
  import ./opengl/glcontext
  export glutils

const FastShadows {.booldefine: "figuro.fastShadows".}: bool = false

type NoRendererBackendState* = object

type FigRenderer*[BackendState = NoRendererBackendState] = ref object
  ctx*: BackendContext
  backendState*: BackendState
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    fallbackAtlasSize: int
    fallbackPixelate: bool
    fallbackPixelScale: float32
    forceOpenGlByEnv: bool

template entries*(ctx: BackendContext): untyped =
  ctx.entriesPtr()[]

proc backendKind*[BackendState](
    renderer: FigRenderer[BackendState]
): RendererBackendKind =
  renderer.ctx.kind()

proc backendName*[BackendState](renderer: FigRenderer[BackendState]): string =
  backendName(renderer.backendKind())

proc runtimeForceOpenGlRequested*(): bool =
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    let force = getEnv("FIGDRAW_FORCE_OPENGL").strip().toLowerAscii()
    if force in ["1", "true", "yes", "on"]:
      return true
    let backend = getEnv("FIGDRAW_BACKEND").strip().toLowerAscii()
    if backend.len > 0:
      return backend in ["opengl", "gl"]
    false
  else:
    false

proc forceOpenGlByEnv*[BackendState](renderer: FigRenderer[BackendState]): bool =
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    renderer.forceOpenGlByEnv
  else:
    discard renderer
    false

when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
  proc logOpenGlFallback(reason: string) =
    warn "Preferred backend failed, falling back to OpenGL at runtime",
      preferredBackend = backendName(PreferredBackendKind), backendError = reason

  proc useOpenGlFallback*[BackendState](
      renderer: FigRenderer[BackendState], reason: string
  ) =
    logOpenGlFallback(reason)
    let alreadyOpenGl = not renderer.ctx.isNil and renderer.ctx.kind() == rbOpenGL
    if alreadyOpenGl:
      return
    try:
      renderer.ctx = opengl_context.newContext(
        atlasSize = renderer.fallbackAtlasSize,
        pixelate = renderer.fallbackPixelate,
        pixelScale = renderer.fallbackPixelScale,
      )
    except CatchableError as glExc:
      raise newException(
        ValueError,
        "Preferred backend failed (" & reason &
          "), and OpenGL fallback could not initialize (" & glExc.msg & ")",
      )

  proc applyRuntimeBackendOverride*[BackendState](
      renderer: FigRenderer[BackendState]
  ): bool =
    if renderer.forceOpenGlByEnv and renderer.backendKind() != rbOpenGL:
      renderer.useOpenGlFallback("forced by FIGDRAW_BACKEND/FIGDRAW_FORCE_OPENGL")
      return true
    false

proc takeScreenshot*[BackendState](
    renderer: FigRenderer[BackendState],
    frame: Rect = rect(0, 0, 0, 0),
    readFront: bool = true,
): Image =
  renderer.ctx.readPixels(frame, readFront = readFront)

proc logBackend(msg: static string) =
  info msg, preferredBackend = backendName(PreferredBackendKind)

proc initRendererContext[BackendState](
    renderer: FigRenderer[BackendState],
    atlasSize: int,
    pixelScale: float32,
    pixelate = false,
) =
  logBackend("Setting up preferred backend")
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    renderer.fallbackAtlasSize = atlasSize
    renderer.fallbackPixelate = pixelate
    renderer.fallbackPixelScale = pixelScale
    renderer.forceOpenGlByEnv = runtimeForceOpenGlRequested()
    if renderer.forceOpenGlByEnv:
      logBackend(
        "Runtime OpenGL override requested; deferring backend swap to setupBackend"
      )
    try:
      renderer.ctx = preferred_backend.newContext(
        atlasSize = atlasSize, pixelate = pixelate, pixelScale = pixelScale
      )
      logBackend("Done setting up preferred backend")
    except CatchableError as exc:
      renderer.useOpenGlFallback(exc.msg)
  elif UseMetalBackend:
    renderer.ctx =
      newContext(atlasSize = atlasSize, pixelate = pixelate, pixelScale = pixelScale)
  elif UseVulkanBackend:
    renderer.ctx = vulkan_context.newContext(
      atlasSize = atlasSize, pixelate = pixelate, pixelScale = pixelScale
    )
  else:
    renderer.ctx =
      newContext(atlasSize = atlasSize, pixelate = pixelate, pixelScale = pixelScale)

proc newFigRenderer*(
    atlasSize: int, pixelScale = 1.0'f32
): FigRenderer[NoRendererBackendState] =
  result = FigRenderer[NoRendererBackendState]()
  result.initRendererContext(atlasSize, pixelScale, pixelate = false)

proc newFigRenderer*[BackendState](
    atlasSize: int, backendState: BackendState, pixelScale = 1.0'f32
): FigRenderer[BackendState] =
  result = FigRenderer[BackendState](backendState: backendState)
  result.initRendererContext(atlasSize, pixelScale, pixelate = false)

proc newFigRenderer*(ctx: BackendContext): FigRenderer[NoRendererBackendState] =
  ## Uses a caller-created backend context.
  result = FigRenderer[NoRendererBackendState](ctx: ctx)

proc newFigRenderer*[BackendState](
    ctx: BackendContext, backendState: BackendState
): FigRenderer[BackendState] =
  ## Uses a caller-created backend context with custom backend state payload.
  result = FigRenderer[BackendState](ctx: ctx, backendState: backendState)

proc renderDrawable*(ctx: BackendContext, node: Fig) =
  ## TODO: draw non-node stuff?
  let box = node.screenBox.scaled()
  for point in node.points:
    let
      pos = point.scaled()
      bx = box.atXY(pos.x, pos.y)
    ctx.drawRect(bx, node.fill)

proc renderText(ctx: BackendContext, node: Fig) {.forbids: [AppMainThreadEff].} =
  ## Draw characters (glyphs)
  if NfSelectText in node.flags and node.fill.a > 0:
    let rects = node.textLayout.selectionRects
    if rects.len > 0 and node.selectionRange.a <= node.selectionRange.b:
      let startIdx = max(node.selectionRange.a, 0)
      let endIdx = min(node.selectionRange.b, rects.len - 1)
      for idx in startIdx .. endIdx:
        let rect = rects[idx].scaled()
        if rect.w > 0 and rect.h > 0:
          ctx.drawRect(rect, node.fill)

  for glyph in node.textLayout.glyphs():
    if unicode.isWhiteSpace(glyph.rune):
      continue

    let
      glyphId = glyph.hash()
      lhDelta = figUiScale() * glyph.lineHeight
      charPos = vec2(glyph.pos.x.scaled(), scaled(glyph.pos.y - glyph.descent))
    if glyphId notin ctx.entries:
      glyph.generateGlyph()
      warn "missing glyph image in context",
        glyphId = glyphId, glyphRune = $glyph.rune, glyphRuneRepr = repr(glyph.rune)
      continue
    ctx.drawImage(glyphId, charPos, glyph.color)

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

#proc drawMasks(ctx: BackendContext, node: Fig) =
#  ctx.setMaskRect(node.screenBox.scaled(), node.corners.scaledCorners())

proc renderDropShadows(ctx: BackendContext, node: Fig) =
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
        mode = figbackend.SdfMode.sdfModeDropShadow,
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

proc renderInnerShadows(ctx: BackendContext, node: Fig) =
  ## drawing inner shadows with various techniques
  for shadow in node.shadows:
    if shadow.style != InnerShadow:
      continue
    if shadow.blur <= 0.0 and shadow.spread <= 0.0:
      continue
    if shadow.color.a <= 0.0:
      continue

    when not defined(useFigDrawTextures):
      let
        box = node.screenBox.scaled()
        shadowOffset = vec2(shadow.x.scaled(), shadow.y.scaled())
        shadowBlur = shadow.blur.scaled()
        shadowSpread = shadow.spread.scaled()
      # For inset mode, shapeSize carries shadow offset (x, y).
      # Backend shader evaluates clip distance from the node shape and shadow
      # distance from an offset shape in a single pass.
      ctx.drawRoundedRectSdf(
        rect = box,
        shapeSize = shadowOffset,
        color = shadow.color,
        radii = node.corners.scaledCorners(),
        mode = figbackend.SdfMode.sdfModeInsetShadow,
        factor = shadowBlur,
        spread = shadowSpread,
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

proc renderBoxes(ctx: BackendContext, node: Fig) =
  ## drawing boxes for rectangles

  let
    box = node.screenBox.scaled()
    corners = node.corners.scaledCorners()

  if node.fill.a > 0'f32:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = box,
        color = node.fill,
        radii = corners,
        mode = figbackend.SdfMode.sdfModeClipAA,
        factor = 4.0'f32,
        spread = 0.0'f32,
        shapeSize = vec2(0.0'f32, 0.0'f32),
      )
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
        mode = figbackend.SdfMode.sdfModeAnnularAA,
        factor = node.stroke.weight.scaled(),
        spread = 0.0'f32,
        shapeSize = vec2(0.0'f32, 0.0'f32),
      )
    else:
      ctx.drawRoundedRect(
        rect = box,
        color = node.stroke.color,
        radii = corners,
        weight = node.stroke.weight.scaled(),
        doStroke = true,
      )

proc renderImage(ctx: BackendContext, node: Fig) =
  if node.image.id.int == 0:
    return
  let box = node.screenBox.scaled()
  let size = vec2(box.w, box.h)
  ctx.drawImage(node.image.id.Hash, pos = box.xy, color = node.image.color, size = size)

proc renderMsdfImage(ctx: BackendContext, node: Fig) =
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
  let strokeWeight = max(0.0'f32, node.msdfImage.strokeWeight).scaled()
  ctx.drawMsdfImage(
    node.msdfImage.id.Hash,
    pos = box.xy,
    color = node.msdfImage.color,
    size = size,
    pxRange = pxRange,
    sdThreshold = sdThreshold,
    strokeWeight = strokeWeight,
  )

proc renderMtsdfImage(ctx: BackendContext, node: Fig) =
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
  let strokeWeight = max(0.0'f32, node.mtsdfImage.strokeWeight).scaled()
  ctx.drawMtsdfImage(
    node.mtsdfImage.id.Hash,
    pos = box.xy,
    color = node.mtsdfImage.color,
    size = size,
    pxRange = pxRange,
    sdThreshold = sdThreshold,
    strokeWeight = strokeWeight,
  )

proc render(
    ctx: BackendContext, nodes: seq[Fig], nodeIdx, parentIdx: FigIdx
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
    ctx.beginMask(node.screenBox.scaled(), node.corners.scaledCorners())
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
          ctx.beginMask(node.screenBox.scaled(), node.corners.scaledCorners())
          ctx.endMask()
          ctx.renderInnerShadows(node)
          ctx.popMask()
      else:
        ctx.renderInnerShadows(node)

  for childIdx in childIndex(nodes, nodeIdx):
    ctx.render(nodes, childIdx, nodeIdx)

  postRender()

proc renderRoot*(
    ctx: BackendContext, nodes: var Renders
) {.forbids: [AppMainThreadEff].} =
  ## draw roots for each level
  var img: ImgObj
  while imageChan.tryRecv(img):
    trace "image loaded", id = $img.id.Hash
    ctx.putImage(img)

  for zlvl, list in nodes.layers.pairs():
    for rootIdx in list.rootIds:
      ctx.render(list.nodes, rootIdx, -1.FigIdx)

proc renderFrame*[BackendState](
    renderer: FigRenderer[BackendState],
    nodes: var Renders,
    frameSize: Vec2,
    clearMain: bool = true,
    clearColor: Color = color(1.0, 1.0, 1.0, 1.0),
) =
  let frameSize = frameSize.scaled()
  if frameSize.x <= 0 or frameSize.y <= 0:
    return
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    try:
      renderer.ctx.beginFrame(
        frameSize, clearMain = clearMain, clearMainColor = clearColor
      )
    except CatchableError as exc:
      if renderer.ctx.kind() == rbOpenGL:
        raise
      renderer.useOpenGlFallback(exc.msg)
      renderer.ctx.beginFrame(
        frameSize, clearMain = clearMain, clearMainColor = clearColor
      )
  else:
    renderer.ctx.beginFrame(
      frameSize, clearMain = clearMain, clearMainColor = clearColor
    )

  let ctx: BackendContext = renderer.ctx

  ctx.saveTransform()
  ctx.scale(ctx.pixelScale)
  ctx.renderRoot(nodes)
  ctx.restoreTransform()
  ctx.endFrame()

  when defined(testOneFrame) and (UseOpenGlBackend or UseOpenGlFallback):
    ## This is used for test only
    ## Take a screen shot of the first frame and exit.
    var img = takeScreenshot(renderer)
    img.writeFile("screenshot.png")
    quit()
