import std/[hashes, math, os, strutils, tables, unicode]
export tables

import pkg/pixie
import pkg/chroma
import pkg/chronicles

import ./commons
import ./figbackend
import ./fignodes
import ./common/fontglyphs
import ./common/typefaces
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
  textLcdFilteringDesired: bool
  textSubpixelPositioningDesired: bool
  textSubpixelGlyphVariantsDesired: bool
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

proc atlasUsage*[BackendState](renderer: FigRenderer[BackendState]): AtlasUsage =
  ## Returns current backend atlas usage.
  ##
  ## Call from the render/backend thread. Use `atlasUsageSnapshot()` for a cheap
  ## cross-thread last-known value.
  renderer.ctx.atlasUsage()

proc runtimeTextLcdFilteringRequested*(): bool =
  let v1 = getEnv("FIGDRAW_TEXT_LCD_FILTERING").strip().toLowerAscii()
  if v1.len > 0:
    return v1 in ["1", "true", "yes", "on"]
  let v3 = getEnv("FIGDRAW_TEXT_LCD_FILTER").strip().toLowerAscii()
  if v3.len > 0:
    return v3 in ["1", "true", "yes", "on"]
  false

proc runtimeTextSubpixelPositioningRequested*(): bool =
  let v1 = getEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING").strip().toLowerAscii()
  if v1.len > 0:
    return v1 in ["1", "true", "yes", "on"]
  false

proc runtimeTextSubpixelGlyphVariantsRequested*(): bool =
  let v1 = getEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS").strip().toLowerAscii()
  if v1.len > 0:
    return v1 in ["1", "true", "yes", "on"]
  false

proc applyTextRuntimeFlags[BackendState](renderer: FigRenderer[BackendState]) =
  if renderer.ctx.isNil:
    return
  renderer.ctx.setTextLcdFilteringEnabled(renderer.textLcdFilteringDesired)
  renderer.ctx.setTextSubpixelPositioningEnabled(
    renderer.textSubpixelPositioningDesired
  )
  renderer.ctx.setTextSubpixelGlyphVariantsEnabled(
    renderer.textSubpixelGlyphVariantsDesired
  )

proc setTextLcdFiltering*[BackendState](
    renderer: FigRenderer[BackendState], enabled: bool
) =
  renderer.textLcdFilteringDesired = enabled
  renderer.ctx.setTextLcdFilteringEnabled(enabled)

proc textLcdFiltering*[BackendState](renderer: FigRenderer[BackendState]): bool =
  renderer.ctx.textLcdFilteringEnabled()

proc setTextSubpixelPositioning*[BackendState](
    renderer: FigRenderer[BackendState], enabled: bool
) =
  renderer.textSubpixelPositioningDesired = enabled
  renderer.ctx.setTextSubpixelPositioningEnabled(enabled)

proc textSubpixelPositioning*[BackendState](renderer: FigRenderer[BackendState]): bool =
  renderer.ctx.textSubpixelPositioningEnabled()

proc setTextSubpixelGlyphVariants*[BackendState](
    renderer: FigRenderer[BackendState], enabled: bool
) =
  renderer.textSubpixelGlyphVariantsDesired = enabled
  renderer.ctx.setTextSubpixelGlyphVariantsEnabled(enabled)

proc textSubpixelGlyphVariants*[BackendState](
    renderer: FigRenderer[BackendState]
): bool =
  renderer.ctx.textSubpixelGlyphVariantsEnabled()

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
      renderer.applyTextRuntimeFlags()
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

proc takeOneFrameScreenshot*[BackendState](
    renderer: FigRenderer[BackendState], frame: Rect = rect(0, 0, 0, 0)
): Image =
  ## Captures the frame that was just rendered by renderFrame().
  ## OpenGL draws into the back buffer until the windowing layer swaps.
  renderer.takeScreenshot(frame, readFront = renderer.backendKind() != rbOpenGL)

proc logBackend(msg: static string) =
  info msg, preferredBackend = backendName(PreferredBackendKind)

proc initRendererContext[BackendState](
    renderer: FigRenderer[BackendState],
    atlasSize: int,
    pixelScale: float32,
    pixelate = false,
) =
  logBackend("Setting up preferred backend")
  renderer.textLcdFilteringDesired = runtimeTextLcdFilteringRequested()
  renderer.textSubpixelPositioningDesired = runtimeTextSubpixelPositioningRequested()
  renderer.textSubpixelGlyphVariantsDesired =
    runtimeTextSubpixelGlyphVariantsRequested()
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
  renderer.applyTextRuntimeFlags()

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
  result.textLcdFilteringDesired = runtimeTextLcdFilteringRequested()
  result.textSubpixelPositioningDesired = runtimeTextSubpixelPositioningRequested()
  result.textSubpixelGlyphVariantsDesired = runtimeTextSubpixelGlyphVariantsRequested()
  result.applyTextRuntimeFlags()

proc newFigRenderer*[BackendState](
    ctx: BackendContext, backendState: BackendState
): FigRenderer[BackendState] =
  ## Uses a caller-created backend context with custom backend state payload.
  result = FigRenderer[BackendState](ctx: ctx, backendState: backendState)
  result.textLcdFilteringDesired = runtimeTextLcdFilteringRequested()
  result.textSubpixelPositioningDesired = runtimeTextSubpixelPositioningRequested()
  result.textSubpixelGlyphVariantsDesired = runtimeTextSubpixelGlyphVariantsRequested()
  result.applyTextRuntimeFlags()

func fillAlphaMax(fill: Fill): uint8
func gradientMidPos01(fill: Fill): float32
func fillCenterColor(fill: Fill): Color
func gradientColors(fill: Fill): array[4, ColorRGBA]

proc glyphScreenPos*(
    nodeBox: Rect, glyphPos: Vec2, glyphDescent: float32
): Vec2 {.inline.} =
  ## Converts a local glyph position into screen-space coordinates.
  vec2(
    glyphPos.x.scaled() + nodeBox.x.scaled(),
    scaled(glyphPos.y - glyphDescent) + nodeBox.y.scaled(),
  )

proc glyphScreenPosInverted*(
    nodeBox: Rect, layoutBounds: Rect, glyphX: float32, glyphRect: Rect
): Vec2 {.inline.} =
  ## Converts a local glyph position into screen-space coordinates with Y-inverted
  ## text layout (line order + glyph placement), mirrored around content bounds.
  let invertedTop = layoutBounds.y + layoutBounds.h - (glyphRect.y + glyphRect.h)
  vec2(glyphX.scaled() + nodeBox.x.scaled(), scaled(invertedTop) + nodeBox.y.scaled())

proc selectionScreenRect*(nodeBox: Rect, selectionRect: Rect): Rect {.inline.} =
  ## Converts a local text selection rectangle into screen-space coordinates.

  rect(
    selectionRect.x + nodeBox.x,
    selectionRect.y + nodeBox.y,
    selectionRect.w,
    selectionRect.h,
  )
  .scaled()

proc selectionLocalRectInverted*(
    layoutBounds: Rect, selectionRect: Rect
): Rect {.inline.} =
  ## Mirrors a local text selection rectangle along the content bounds' Y axis.
  rect(
    selectionRect.x,
    layoutBounds.y + layoutBounds.h - (selectionRect.y + selectionRect.h),
    selectionRect.w,
    selectionRect.h,
  )

proc glyphLocalPos*(glyphPos: Vec2, glyphDescent: float32): Vec2 {.inline.} =
  ## Converts a local glyph baseline position into local glyph top-left coordinates.
  vec2(glyphPos.x.scaled(), scaled(glyphPos.y - glyphDescent))

proc renderText(ctx: BackendContext, node: Fig) {.forbids: [AppMainThreadEff].} =
  ## Render characters (glyphs)
  let
    lcdFiltering = ctx.textLcdFilteringEnabled()
    subpixelPositioning = ctx.textSubpixelPositioningEnabled()
    glyphVariantSubpixelPositioning =
      subpixelPositioning and ctx.textSubpixelGlyphVariantsEnabled()

  ctx.saveTransform()
  block:
    ctx.translate(node.screenBox.xy.scaled())
    if NfInvertY in node.flags:
      # Mirror in local text-box coordinates so first-line top offset/padding is
      # preserved instead of swapping Top/Bottom alignment.
      let invertPivotY = scaled(node.screenBox.h)
      ctx.translate(vec2(0.0'f32, invertPivotY))
      ctx.scale(vec2(1.0'f32, -1.0'f32))

    if NfSelectText in node.flags and fillAlphaMax(node.fill) > 0'u8 and
        node.selectionRange.a <= node.selectionRange.b:
      let
        sourceRange = node.selectionRange.a.int .. node.selectionRange.b.int
        zeroRadii = [0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32]
      for selection in node.textLayout.selectionRectsFor(sourceRange):
        if selection.h > 0:
          let selectionRect =
            rect(selection.x, selection.y, max(selection.w, 1.0'f32), selection.h)
          ctx.drawRoundedRectSdf(
            rect = selectionRect.scaled(),
            fill = node.fill.toBackendFill(),
            radii = zeroRadii,
            mode = figbackend.SdfMode.sdfModeClipAA,
            factor = 4.0'f32,
            spread = 0.0'f32,
            shapeSize = vec2(0.0'f32, 0.0'f32),
          )

    for glyph in node.textLayout.glyphs():
      if glyph.isWhitespace:
        continue

      var
        glyphPos = glyphLocalPos(glyph.pos, glyph.descent) + glyph.imageOffset.scaled()
        subpixelShift = 0.0'f32
        subpixelVariant = 0
      if subpixelPositioning:
        let snappedX = floor(glyphPos.x)
        let fractionalX = max(0.0'f32, min(glyphPos.x - snappedX, 0.999'f32))
        glyphPos.x = snappedX
        if glyphVariantSubpixelPositioning:
          subpixelVariant = toGlyphVariantSubpixelStep(fractionalX)
        else:
          subpixelShift = fractionalX

      let glyphId =
        glyph.hash(lcdFiltering = lcdFiltering, subpixelVariant = subpixelVariant)

      ctx.setTextSubpixelShift(subpixelShift)
      if glyphId notin ctx.entries:
        let img = glyph.generateGlyph(
          lcdFiltering = lcdFiltering,
          subpixelVariant = subpixelVariant,
          force = true,
          upload = false,
        )
        if img != nil:
          ctx.putImage(glyphId, img)
          ctx.markGlyphEntry(glyphId, glyph.fontId, getFigFont(glyph.fontId).typefaceId)
        if glyphId notin ctx.entries:
          debug "missing glyph image in context",
            glyphId = glyphId, glyphRune = $glyph.rune, glyphRuneRepr = repr(glyph.rune)
          ctx.setTextSubpixelShift(0.0'f32)
          continue

      ctx.drawImage(glyphId, glyphPos, glyph.fill.gradientColors(), false)
      if subpixelPositioning:
        ctx.setTextSubpixelShift(0.0'f32)
  ctx.setTextSubpixelShift(0.0'f32)
  ctx.restoreTransform()

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
    corners: array[DirectionCorners, uint16]
): array[DirectionCorners, float32] =
  for corner in DirectionCorners:
    result[corner] = corners[corner].float32.scaled()

func lerpColor(a, b: ColorRGBA, t: float32): ColorRGBA =
  let
    clampedT = clamp(t, 0.0'f32, 1.0'f32)
    invT = 1.0'f32 - clampedT
  result.r = (a.r.float32 * invT + b.r.float32 * clampedT).round().uint8
  result.g = (a.g.float32 * invT + b.g.float32 * clampedT).round().uint8
  result.b = (a.b.float32 * invT + b.b.float32 * clampedT).round().uint8
  result.a = (a.a.float32 * invT + b.a.float32 * clampedT).round().uint8

func fillAlphaMax(fill: Fill): uint8 =
  case fill.kind
  of flColor:
    fill.color.a
  of flLinear2:
    max(fill.lin2.start.a, fill.lin2.stop.a)
  of flLinear3:
    max(fill.lin3.start.a, max(fill.lin3.mid.a, fill.lin3.stop.a))

func gradientMidPos01(fill: Fill): float32 =
  case fill.kind
  of flLinear3:
    clamp(fill.lin3.midPos.float32 / 255.0'f32, 0.01'f32, 0.99'f32)
  else:
    0.5'f32

func sampleGradientColor(fill: Fill, t: float32): ColorRGBA =
  case fill.kind
  of flColor:
    fill.color
  of flLinear2:
    lerpColor(fill.lin2.start, fill.lin2.stop, t)
  of flLinear3:
    let
      clampedT = clamp(t, 0.0'f32, 1.0'f32)
      mid = gradientMidPos01(fill)
    if clampedT <= mid:
      lerpColor(fill.lin3.start, fill.lin3.mid, clampedT / mid)
    else:
      lerpColor(fill.lin3.mid, fill.lin3.stop, (clampedT - mid) / (1.0'f32 - mid))

func fillCenterColor(fill: Fill): Color =
  fill.sampleGradientColor(0.5'f32).color

func fillGradientAxis(fill: Fill): FillGradientAxis =
  case fill.kind
  of flLinear2: fill.lin2.axis
  of flLinear3: fill.lin3.axis
  of flColor: fgaX

func gradientColors(fill: Fill): array[4, ColorRGBA] =
  ## Vertex order: 0=BL, 1=BR, 2=TR, 3=TL
  case fill.fillGradientAxis()
  of fgaX:
    result[0] = fill.sampleGradientColor(0.0'f32)
    result[1] = fill.sampleGradientColor(1.0'f32)
    result[2] = fill.sampleGradientColor(1.0'f32)
    result[3] = fill.sampleGradientColor(0.0'f32)
  of fgaY:
    result[0] = fill.sampleGradientColor(1.0'f32)
    result[1] = fill.sampleGradientColor(1.0'f32)
    result[2] = fill.sampleGradientColor(0.0'f32)
    result[3] = fill.sampleGradientColor(0.0'f32)
  of fgaDiagTLBR:
    result[0] = fill.sampleGradientColor(0.5'f32)
    result[1] = fill.sampleGradientColor(1.0'f32)
    result[2] = fill.sampleGradientColor(0.5'f32)
    result[3] = fill.sampleGradientColor(0.0'f32)
  of fgaDiagBLTR:
    result[0] = fill.sampleGradientColor(0.0'f32)
    result[1] = fill.sampleGradientColor(0.5'f32)
    result[2] = fill.sampleGradientColor(1.0'f32)
    result[3] = fill.sampleGradientColor(0.5'f32)

#proc drawMasks(ctx: BackendContext, node: Fig) =
#  ctx.setMaskRect(node.screenBox.scaled(), node.corners.scaledCorners())

proc renderDropShadows(ctx: BackendContext, node: Fig) =
  ## drawing shadows with various techniques
  for shadow in node.shadows:
    if shadow.style != DropShadow:
      continue
    if shadow.blur <= 0.0 and shadow.spread <= 0.0:
      continue
    let shadowColor = fillCenterColor(shadow.fill)
    if fillAlphaMax(shadow.fill) == 0'u8:
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
        fill = shadow.fill.toBackendFill(),
        radii = node.corners.scaledCorners(),
        mode = figbackend.SdfMode.sdfModeDropShadow,
        factor = shadowBlur,
        spread = shadowSpread,
      )
    elif FastShadows:
      ## should add a primitive to opengl.context to
      var color = shadowColor
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
        shadowColor = shadowColor,
        innerShadow = false,
      )

proc renderInnerShadows(ctx: BackendContext, node: Fig) =
  ## drawing inner shadows with various techniques
  for shadow in node.shadows:
    if shadow.style != InnerShadow:
      continue
    if shadow.blur <= 0.0 and shadow.spread <= 0.0:
      continue
    if fillAlphaMax(shadow.fill) == 0'u8:
      continue
    let shadowColor = fillCenterColor(shadow.fill)

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
        fill = shadow.fill.toBackendFill(),
        radii = node.corners.scaledCorners(),
        mode = figbackend.SdfMode.sdfModeInsetShadow,
        factor = shadowBlur,
        spread = shadowSpread,
      )
    elif FastShadows:
      ## this is even more incorrect than drop shadows, but it's something
      ## and I don't actually want to think today ;)
      let n = shadow.blur.scaled().toInt
      var color = shadowColor
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
        shadowColor = shadowColor,
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
    if fillAlphaMax(shadow.fill) == 0'u8:
      continue
    return true
  return false

func zeroCorners(): array[DirectionCorners, uint16] =
  for corner in DirectionCorners:
    result[corner] = 0'u16

func uniformCorners(radius: uint16): array[DirectionCorners, uint16] =
  for corner in DirectionCorners:
    result[corner] = radius

func radiusCorner(radius: float32): uint16 =
  if radius <= 0.0'f32:
    return 0'u16
  if radius >= high(uint16).float32:
    return high(uint16)
  round(radius).uint16

proc renderRoundedShape(
    ctx: BackendContext,
    shapeBox: Rect,
    shapeFill: Fill,
    shapeStroke: RenderStroke,
    shapeCorners: array[DirectionCorners, uint16],
) =
  let
    box = shapeBox.scaled()
    corners = shapeCorners.scaledCorners()
    hasGradient =
      shapeFill.kind in {flLinear2, flLinear3} and fillAlphaMax(shapeFill) > 0'u8

  if hasGradient:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = box,
        fill = shapeFill.toBackendFill(),
        radii = corners,
        mode = figbackend.SdfMode.sdfModeClipAA,
        factor = 4.0'f32,
        spread = 0.0'f32,
        shapeSize = vec2(0.0'f32, 0.0'f32),
      )
    else:
      let fillColor = fillCenterColor(shapeFill)
      if shapeCorners != [0'u16, 0'u16, 0'u16, 0'u16]:
        ctx.drawRoundedRect(rect = box, color = fillColor, radii = corners)
      else:
        ctx.drawRect(box, fillColor)
  elif fillAlphaMax(shapeFill) > 0'u8:
    let fillColor = fillCenterColor(shapeFill)
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = box,
        color = fillColor,
        radii = corners,
        mode = figbackend.SdfMode.sdfModeClipAA,
        factor = 4.0'f32,
        spread = 0.0'f32,
        shapeSize = vec2(0.0'f32, 0.0'f32),
      )
    else:
      if shapeCorners != [0'u16, 0'u16, 0'u16, 0'u16]:
        ctx.drawRoundedRect(rect = box, color = fillColor, radii = corners)
      else:
        ctx.drawRect(box, fillColor)

  if fillAlphaMax(shapeStroke.fill) > 0'u8 and shapeStroke.weight > 0:
    when not defined(useFigDrawTextures):
      ctx.drawRoundedRectSdf(
        rect = box,
        fill = shapeStroke.fill.toBackendFill(),
        radii = corners,
        mode = figbackend.SdfMode.sdfModeAnnularAA,
        factor = shapeStroke.weight.scaled(),
        spread = 0.0'f32,
        shapeSize = vec2(0.0'f32, 0.0'f32),
      )
    else:
      ctx.drawRoundedRect(
        rect = box,
        color = fillCenterColor(shapeStroke.fill),
        radii = corners,
        weight = shapeStroke.weight.scaled(),
        doStroke = true,
      )

proc renderDrawableLine(
    ctx: BackendContext, origin: Vec2, op: DrawableOp, stroke: RenderStroke
) =
  let weight = max(0.0'f32, stroke.weight)
  if weight <= 0.0'f32 or fillAlphaMax(stroke.fill) == 0'u8:
    return

  let
    a = origin + op.a
    b = origin + op.b
    delta = b - a
    length = sqrt(delta.x * delta.x + delta.y * delta.y)
  if length <= 0.0'f32:
    return

  let
    center = (a + b) / 2.0'f32
    box = rect(center.x - length / 2.0'f32, center.y - weight / 2.0'f32, length, weight)
    scaledBox = box.scaled()
    pivot = scaledBox.xy + scaledBox.wh / 2.0'f32
    angle = arctan2(delta.y, delta.x).float32

  ctx.saveTransform()
  try:
    ctx.translate(pivot)
    ctx.rotate(angle)
    ctx.translate(-pivot)
    ctx.renderRoundedShape(box, stroke.fill, RenderStroke(), zeroCorners())
  finally:
    ctx.restoreTransform()

proc renderDrawableStrokeCap(
    ctx: BackendContext, center: Vec2, radius: float32, fill: Fill
) =
  if radius <= 0.0'f32 or fillAlphaMax(fill) == 0'u8:
    return

  let
    diameter = radius * 2.0'f32
    box = rect(center.x - radius, center.y - radius, diameter, diameter)
  ctx.renderRoundedShape(
    box, fill, RenderStroke(), uniformCorners(radius.radiusCorner())
  )

proc renderDrawableCircle(
    ctx: BackendContext, origin: Vec2, op: DrawableOp, fill: Fill, stroke: RenderStroke
) =
  let radius = max(0.0'f32, op.radius)
  if radius <= 0.0'f32:
    return

  let
    diameter = radius * 2.0'f32
    box = rect(
      origin.x + op.center.x - radius,
      origin.y + op.center.y - radius,
      diameter,
      diameter,
    )
  ctx.renderRoundedShape(box, fill, stroke, uniformCorners(radius.radiusCorner()))

proc renderDrawableRect(
    ctx: BackendContext, origin: Vec2, op: DrawableOp, fill: Fill, stroke: RenderStroke
) =
  let box = rect(origin.x + op.box.x, origin.y + op.box.y, op.box.w, op.box.h)
  ctx.renderRoundedShape(box, fill, stroke, op.corners)

proc bezierPoint(controls: openArray[Vec2], t: float32): Vec2 =
  if controls.len == 0:
    return vec2(0.0'f32, 0.0'f32)

  var work = newSeq[Vec2](controls.len)
  for i, point in controls:
    work[i] = point

  var count = controls.len
  while count > 1:
    for i in 0 ..< (count - 1):
      work[i] = work[i] * (1.0'f32 - t) + work[i + 1] * t
    dec count
  work[0]

func drawableStepCount(steps, nodeSteps, fallback: uint16): int =
  let resolved =
    if steps != 0'u16:
      steps
    elif nodeSteps != 0'u16:
      nodeSteps
    else:
      fallback
  max(1, resolved.int)

func bezierStepCount(op: DrawableOp, nodeSteps: uint16): int =
  drawableStepCount(op.steps, nodeSteps, DefaultDrawableBezierSteps)

func arcStepCount(op: DrawableOp, nodeSteps: uint16): int =
  drawableStepCount(op.arcSteps, nodeSteps, DefaultDrawableArcSteps)

proc renderDrawableBezier(
    ctx: BackendContext,
    origin: Vec2,
    op: DrawableOp,
    stroke: RenderStroke,
    nodeSteps: uint16,
) =
  if op.controls.len < 2:
    return
  if stroke.weight <= 0.0'f32 or fillAlphaMax(stroke.fill) == 0'u8:
    return

  let steps = op.bezierStepCount(nodeSteps)
  let capRadius = max(0.0'f32, stroke.weight) / 2.0'f32
  var previous = bezierPoint(op.controls, 0.0'f32)
  ctx.renderDrawableStrokeCap(origin + previous, capRadius, stroke.fill)
  for step in 1 .. steps:
    let
      t = step.float32 / steps.float32
      current = bezierPoint(op.controls, t)
      segment = drawableLine(previous, current)
    ctx.renderDrawableLine(origin, segment, stroke)
    ctx.renderDrawableStrokeCap(origin + current, capRadius, stroke.fill)
    previous = current

func arcPoint(center: Vec2, radius, angle: float32): Vec2 =
  center + vec2(cos(angle) * radius, sin(angle) * radius)

proc renderDrawableArc(
    ctx: BackendContext,
    origin: Vec2,
    op: DrawableOp,
    stroke: RenderStroke,
    nodeSteps: uint16,
) =
  let radius = max(0.0'f32, op.arcRadius)
  if radius <= 0.0'f32 or op.sweepAngle == 0.0'f32:
    return
  if stroke.weight <= 0.0'f32 or fillAlphaMax(stroke.fill) == 0'u8:
    return

  let steps = op.arcStepCount(nodeSteps)
  let capRadius = max(0.0'f32, stroke.weight) / 2.0'f32
  var previous = arcPoint(op.arcCenter, radius, op.startAngle)
  ctx.renderDrawableStrokeCap(origin + previous, capRadius, stroke.fill)
  for step in 1 .. steps:
    let
      t = step.float32 / steps.float32
      angle = op.startAngle + op.sweepAngle * t
      current = arcPoint(op.arcCenter, radius, angle)
      segment = drawableLine(previous, current)
    ctx.renderDrawableLine(origin, segment, stroke)
    ctx.renderDrawableStrokeCap(origin + current, capRadius, stroke.fill)
    previous = current

proc renderDrawable*(ctx: BackendContext, node: Fig) =
  let
    origin = node.screenBox.xy
    fill = node.fill
    stroke = node.drawStroke
    nodeSteps = node.drawSteps
  for op in node.drawOps:
    case op.kind
    of dkLine:
      ctx.renderDrawableLine(origin, op, stroke)
    of dkCircle:
      ctx.renderDrawableCircle(origin, op, fill, stroke)
    of dkRectangle:
      ctx.renderDrawableRect(origin, op, fill, stroke)
    of dkBezier:
      ctx.renderDrawableBezier(origin, op, stroke, nodeSteps)
    of dkArc:
      ctx.renderDrawableArc(origin, op, stroke, nodeSteps)

proc renderBoxes(ctx: BackendContext, node: Fig) =
  ## drawing boxes for rectangles
  ctx.renderRoundedShape(node.screenBox, node.fill, node.stroke, node.corners)

proc renderImage(ctx: BackendContext, node: Fig) =
  if node.image.id.int == 0:
    return
  let box = node.screenBox.scaled()
  let size = vec2(box.w, box.h)
  ctx.drawImage(
    node.image.id.Hash,
    pos = box.xy,
    color = fillCenterColor(node.image.fill),
    size = size,
    flipY = NfInvertY in node.flags,
  )

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
    color = fillCenterColor(node.msdfImage.fill),
    size = size,
    pxRange = pxRange,
    sdThreshold = sdThreshold,
    strokeWeight = strokeWeight,
    flipY = NfInvertY in node.flags,
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
    color = fillCenterColor(node.mtsdfImage.fill),
    size = size,
    pxRange = pxRange,
    sdThreshold = sdThreshold,
    strokeWeight = strokeWeight,
    flipY = NfInvertY in node.flags,
  )

proc renderBackdropBlur(ctx: BackendContext, node: Fig) =
  let box = node.screenBox.scaled()
  if node.backdropBlur.blur > 0.0'f32:
    ctx.drawBackdropBlur(
      rect = box,
      radii = node.corners.scaledCorners(),
      blurRadius = node.backdropBlur.blur.scaled(),
    )

  if fillAlphaMax(node.fill) == 0'u8:
    return

  var overlay = Fig(kind: nkRectangle)
  overlay.screenBox = node.screenBox
  overlay.fill = node.fill
  overlay.corners = node.corners
  overlay.stroke = RenderStroke(weight: 0.0'f32, fill: fill(rgba(0, 0, 0, 0)))
  ctx.renderBoxes(overlay)

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

  ifrender node.kind == nkTransform:
    ctx.saveTransform()
    if node.transform.translation.x != 0.0'f32 or node.transform.translation.y != 0.0'f32:
      ctx.translate(node.transform.translation.scaled())
    if node.transform.useMatrix:
      ctx.applyTransform(node.transform.matrix)
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

  ifrender NfRectMaskContent in node.flags:
    ctx.beginRectMask(node.screenBox.scaled(), node.corners.scaledCorners())
  finally:
    ctx.popRectMask()

  ifrender true:
    if node.kind == nkText:
      ctx.renderText(node)
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
    elif node.kind == nkBackdropBlur:
      ctx.renderBackdropBlur(node)

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
  var legacyImg: ImgObj
  while imageChan.tryRecv(legacyImg):
    trace "image loaded", id = $legacyImg.id.Hash
    case legacyImg.kind
    of PixieImg:
      if legacyImg.pimg == nil:
        debug "skipping nil pixie image", imageId = legacyImg.id.Hash
        continue
    of FlippyImg:
      if legacyImg.flippy.mipmaps.len == 0:
        debug "skipping empty flippy image", imageId = legacyImg.id.Hash
        continue
    ctx.putImage(legacyImg)
    ctx.markImageEntry(legacyImg.id)

  var img: ImageMsg
  while tryRecvImageMsg(img):
    case img.kind
    of ImkPutPixie, ImkPutGlyphPixie:
      trace "image loaded", id = $img.id.Hash
      if not imageMessageCurrent(img):
        debug "skipping stale pixie image", imageId = img.id.Hash
        continue
      if img.pimg == nil:
        debug "skipping nil pixie image", imageId = img.id.Hash
        continue
      var imgObj = ImgObj(id: img.id, kind: PixieImg, pimg: img.pimg)
      ctx.putImage(imgObj)
      if img.kind == ImkPutGlyphPixie:
        ctx.markGlyphEntry(img.id.Hash, img.fontId, img.typefaceId)
      else:
        ctx.markImageEntry(img.id)
    of ImkPutFlippy:
      trace "image loaded", id = $img.id.Hash
      if not imageMessageCurrent(img):
        debug "skipping stale flippy image", imageId = img.id.Hash
        continue
      if img.flippy.mipmaps.len == 0:
        debug "skipping empty flippy image", imageId = img.id.Hash
        continue
      var imgObj = ImgObj(id: img.id, kind: FlippyImg, flippy: move(img.flippy))
      ctx.putImage(imgObj)
      ctx.markImageEntry(img.id)
    of ImkClearImage:
      trace "image cleared", id = $img.id.Hash
      ctx.removeImage(img.id)
    of ImkClearImages:
      trace "images cleared", count = img.ids.len
      for id in img.ids:
        ctx.removeImage(id)
    of ImkClearImageCache:
      trace "image cache cleared"
      ctx.clearImageAtlas()
    of ImkClearFontGlyphs:
      trace "font glyphs cleared", fontId = $Hash(img.fontId)
      ctx.clearFontGlyphs(img.fontId)
    of ImkClearTypefaceGlyphs:
      trace "typeface glyphs cleared", typefaceId = $Hash(img.typefaceId)
      ctx.clearTypefaceGlyphs(img.typefaceId)
    of ImkRetainImage:
      trace "image retained", id = $img.id.Hash
      ctx.retainImageOwner(img.id, img.ownerToken)
    of ImkReleaseImage:
      trace "image released", id = $img.id.Hash
      if ctx.releaseImageOwner(img.id, img.ownerToken):
        forgetReleasedImage(img.id)
        ctx.removeImage(img.id)
    of ImkRetainFont:
      trace "font retained", fontId = $Hash(img.fontId)
      ctx.retainFontOwner(img.fontId, img.ownerToken)
    of ImkReleaseFont:
      trace "font released", fontId = $Hash(img.fontId)
      if ctx.releaseFontOwner(img.fontId, img.ownerToken):
        forgetReleasedFontGlyphs(img.fontId)
        ctx.clearFontGlyphs(img.fontId)

  for zlvl, list in nodes.layers.pairs():
    for rootIdx in list.rootIds:
      ctx.render(list.nodes, rootIdx, -1.FigIdx)

  ctx.publishAtlasUsage()

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
    var img = takeOneFrameScreenshot(renderer)
    img.writeFile("screenshot.png")
    quit()

proc clearImage*[BackendState](renderer: FigRenderer[BackendState], id: ImageId) =
  discard renderer
  clearImage(id)

proc clearImages*[BackendState](
    renderer: FigRenderer[BackendState], ids: openArray[ImageId]
) =
  discard renderer
  clearImages(ids)

proc clearImageCache*[BackendState](renderer: FigRenderer[BackendState]) =
  discard renderer
  clearImageCache()

proc clearFontGlyphs*[BackendState](
    renderer: FigRenderer[BackendState], fontId: FontId
) =
  discard renderer
  clearFontGlyphs(fontId)

proc clearTypefaceGlyphs*[BackendState](
    renderer: FigRenderer[BackendState], typefaceId: TypefaceId
) =
  discard renderer
  clearTypefaceGlyphs(typefaceId)
