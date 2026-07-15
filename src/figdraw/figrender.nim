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

proc atlasGeneration*[BackendState](renderer: FigRenderer[BackendState]): uint64 =
  renderer.ctx.atlasGeneration()

proc atlasRebuildCount*[BackendState](renderer: FigRenderer[BackendState]): uint64 =
  renderer.ctx.atlasRebuildCount()

proc containsImage*[BackendState](
    renderer: FigRenderer[BackendState], id: ImageId
): bool =
  renderer.ctx.hasImage(id.Hash)

proc ensureImage*[BackendState](
    renderer: FigRenderer[BackendState], id: ImageId, image: Image
): bool {.discardable.} =
  if image.isNil or renderer.containsImage(id):
    return false
  var imgObj = ImgObj(id: id, kind: PixieImg, pimg: image)
  renderer.ctx.putImage(imgObj)
  renderer.ctx.markImageEntry(id)
  true

proc rebuildImageAtlas*[BackendState](
    renderer: FigRenderer[BackendState], minimumSize = 0
) =
  renderer.ctx.resetImageAtlas(minimumSize)

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

proc drawTextDecoration(
    ctx: BackendContext, decoration: Rect, color: Fill
) {.forbids: [AppMainThreadEff].} =
  if decoration.w <= 0 or decoration.h <= 0:
    return
  ctx.drawRoundedRectSdf(
    rect = decoration.scaled(),
    fill = color.toBackendFill(),
    radii = [0.0'f32, 0.0'f32, 0.0'f32, 0.0'f32],
    mode = figbackend.SdfMode.sdfModeClipAA,
    factor = 4.0'f32,
    spread = 0.0'f32,
    shapeSize = vec2(0.0'f32, 0.0'f32),
  )

proc renderTextDecorations(
    ctx: BackendContext, arrangement: GlyphArrangement
) {.forbids: [AppMainThreadEff].} =
  for spanIndex, span in arrangement.spans:
    if spanIndex >= arrangement.fonts.len:
      break
    let font = arrangement.fonts[spanIndex]
    if font.underline or font.strikethrough:
      let color =
        if spanIndex < arrangement.spanColors.len:
          arrangement.spanColors[spanIndex]
        else:
          fill(rgba(0, 0, 0, 255))
      let thickness = max(round(font.size / 16.0'f32), 1.0'f32)
      for line in arrangement.lines:
        let
          start = max(span.a, line.a)
          stop = min(span.b, line.b)
        if start <= stop:
          var
            minX = float32.high
            maxX = -float32.high
            minY = float32.high
            maxY = -float32.high
          for glyphIndex in start .. stop:
            let glyphRect = arrangement.glyphRect(glyphIndex)
            minX = min(minX, glyphRect.x)
            maxX = max(maxX, glyphRect.x + glyphRect.w)
            minY = min(minY, glyphRect.y)
            maxY = max(maxY, glyphRect.y + glyphRect.h)

          if minX < maxX and minY < maxY:
            if font.underline:
              ctx.drawTextDecoration(
                rect(minX, maxY - thickness * 1.5'f32, maxX - minX, thickness), color
              )
            if font.strikethrough:
              ctx.drawTextDecoration(
                rect(
                  minX,
                  minY + (maxY - minY) * 0.5'f32 - thickness * 0.5'f32,
                  maxX - minX,
                  thickness,
                ),
                color,
              )

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

    ctx.renderTextDecorations(node.textLayout)

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

func vectorLength(v: Vec2): float32 =
  sqrt(v.x * v.x + v.y * v.y)

func normalizedOr(v, fallback: Vec2): Vec2 =
  let len = vectorLength(v)
  if len <= 0.000001'f32:
    fallback
  else:
    v / len

func normalLeft(dir: Vec2): Vec2 =
  vec2(-dir.y, dir.x)

func cross2(a, b: Vec2): float32 =
  a.x * b.y - a.y * b.x

func resolveLineCap(stroke: RenderStroke): StrokeCap =
  case stroke.cap
  of scAuto: scButt
  else: stroke.cap

func resolveCurveCap(stroke: RenderStroke): StrokeCap =
  case stroke.cap
  of scAuto: scRound
  else: stroke.cap

func resolveCurveJoin(stroke: RenderStroke): StrokeJoin =
  case stroke.join
  of sjAuto: sjRound
  else: stroke.join

func withCap(stroke: RenderStroke, cap: StrokeCap): RenderStroke =
  result = stroke
  result.cap = cap

proc renderDrawableStrokeCap(
  ctx: BackendContext, center: Vec2, radius: float32, fill: Fill
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
    length = vectorLength(delta)
  if length <= 0.0'f32:
    return

  let
    cap = stroke.resolveLineCap()
    capRadius = weight * 0.5'f32
    dir = delta / length
  var
    drawA = a
    drawB = b
    drawLength = length
  if cap == scSquare:
    drawA = a - dir * capRadius
    drawB = b + dir * capRadius
    drawLength = length + weight

  let
    center = (drawA + drawB) / 2.0'f32
    box = rect(
      center.x - drawLength / 2.0'f32, center.y - weight / 2.0'f32, drawLength, weight
    )
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

  if cap == scRound:
    ctx.renderDrawableStrokeCap(a, capRadius, stroke.fill)
    ctx.renderDrawableStrokeCap(b, capRadius, stroke.fill)

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

proc renderDrawableEndpointCap(
    ctx: BackendContext,
    origin, point, tangent: Vec2,
    radius: float32,
    stroke: RenderStroke,
    cap: StrokeCap,
    isStart: bool,
) =
  if radius <= 0.0'f32 or fillAlphaMax(stroke.fill) == 0'u8:
    return

  case cap
  of scRound:
    ctx.renderDrawableStrokeCap(origin + point, radius, stroke.fill)
  of scSquare:
    let
      dir = normalizedOr(tangent, vec2(1.0'f32, 0.0'f32))
      a =
        if isStart:
          point - dir * radius
        else:
          point
      b =
        if isStart:
          point
        else:
          point + dir * radius
    ctx.renderDrawableLine(origin, drawableLine(a, b), stroke.withCap(scButt))
  of scAuto, scButt:
    discard

func lineIntersection(p, r, q, s: Vec2, hit: var Vec2): bool =
  let denom = cross2(r, s)
  if abs(denom) <= 0.000001'f32:
    return false
  let t = cross2(q - p, s) / denom
  hit = p + r * t
  true

proc renderDrawableFilledQuad(ctx: BackendContext, verts: array[4, Vec2], fill: Fill) =
  if fillAlphaMax(fill) == 0'u8:
    return

  let color = fillCenterColor(fill).rgba()
  ctx.drawFilledQuad(
    [verts[0].scaled(), verts[1].scaled(), verts[2].scaled(), verts[3].scaled()],
    [color, color, color, color],
  )

proc renderDrawableStrokeJoin(
    ctx: BackendContext,
    origin, point, incomingTangent, outgoingTangent: Vec2,
    radius: float32,
    fill: Fill,
    join: StrokeJoin,
) =
  if radius <= 0.0'f32 or fillAlphaMax(fill) == 0'u8:
    return

  case join
  of sjRound:
    ctx.renderDrawableStrokeCap(origin + point, radius, fill)
  of sjBevel, sjMiter:
    let
      incoming = normalizedOr(incomingTangent, vec2(1.0'f32, 0.0'f32))
      outgoing = normalizedOr(outgoingTangent, incoming)
      turn = cross2(incoming, outgoing)
    if abs(turn) <= 0.0001'f32:
      return

    let
      side = if turn > 0.0'f32: -1.0'f32 else: 1.0'f32
      incomingOuter = point + normalLeft(incoming) * (radius * side)
      outgoingOuter = point + normalLeft(outgoing) * (radius * side)
    if join == sjMiter:
      var miterPoint: Vec2
      if lineIntersection(incomingOuter, incoming, outgoingOuter, outgoing, miterPoint) and
          vectorLength(miterPoint - point) <= radius * 4.0'f32:
        ctx.renderDrawableFilledQuad(
          [
            origin + point,
            origin + incomingOuter,
            origin + miterPoint,
            origin + outgoingOuter,
          ],
          fill,
        )
        return

    ctx.renderDrawableFilledQuad(
      [
        origin + point,
        origin + incomingOuter,
        origin + outgoingOuter,
        origin + outgoingOuter,
      ],
      fill,
    )
  of sjAuto:
    discard

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

func quadraticPoint(p0, p1, p2: Vec2, t: float32): Vec2 =
  let invT = 1.0'f32 - t
  p0 * (invT * invT) + p1 * (2.0'f32 * invT * t) + p2 * (t * t)

proc includePoint(p: Vec2, minPoint, maxPoint: var Vec2) =
  minPoint.x = min(minPoint.x, p.x)
  minPoint.y = min(minPoint.y, p.y)
  maxPoint.x = max(maxPoint.x, p.x)
  maxPoint.y = max(maxPoint.y, p.y)

func isFlatQuadratic(p0, p1, p2: Vec2): bool =
  abs(cross2(p1 - p0, p2 - p1)) <= 0.0001'f32

const
  DrawableAdaptiveTolerancePx = 0.5'f32
  DrawableSdfPaddingPx = 2.0'f32
  MaxAdaptiveDrawableSteps = max(DefaultDrawableBezierSteps.int * 4, 64)
  MaxAdaptiveCurveDepth = 8

proc drawableSdfPadding(): float32 =
  DrawableSdfPaddingPx.descaled()

proc quadraticBounds(p0, p1, p2: Vec2, padding: float32): Rect =
  var
    minPoint = vec2(min(p0.x, p2.x), min(p0.y, p2.y))
    maxPoint = vec2(max(p0.x, p2.x), max(p0.y, p2.y))

  let denomX = p0.x - 2.0'f32 * p1.x + p2.x
  if abs(denomX) > 0.000001'f32:
    let t = (p0.x - p1.x) / denomX
    if t > 0.0'f32 and t < 1.0'f32:
      includePoint(quadraticPoint(p0, p1, p2, t), minPoint, maxPoint)

  let denomY = p0.y - 2.0'f32 * p1.y + p2.y
  if abs(denomY) > 0.000001'f32:
    let t = (p0.y - p1.y) / denomY
    if t > 0.0'f32 and t < 1.0'f32:
      includePoint(quadraticPoint(p0, p1, p2, t), minPoint, maxPoint)

  rect(
    minPoint.x - padding,
    minPoint.y - padding,
    maxPoint.x - minPoint.x + padding * 2.0'f32,
    maxPoint.y - minPoint.y + padding * 2.0'f32,
  )

func explicitDrawableStepCount(steps, nodeSteps: uint16): int =
  if steps != 0'u16:
    max(1, steps.int)
  elif nodeSteps != 0'u16:
    max(1, nodeSteps.int)
  else:
    0

type DrawableQuadraticSpan = object
  p0, p1, p2: Vec2

func startTangent(span: DrawableQuadraticSpan): Vec2 =
  normalizedOr(
    span.p1 - span.p0, normalizedOr(span.p2 - span.p0, vec2(1.0'f32, 0.0'f32))
  )

func endTangent(span: DrawableQuadraticSpan): Vec2 =
  normalizedOr(
    span.p2 - span.p1, normalizedOr(span.p2 - span.p0, vec2(1.0'f32, 0.0'f32))
  )

proc pointDistancePx(a, b: Vec2): float32 =
  vectorLength((a - b).scaled())

func distanceToLine(p, a, b: Vec2): float32 =
  let ab = b - a
  let denom = ab.x * ab.x + ab.y * ab.y
  if denom <= 0.000001'f32:
    return vectorLength(p - a)
  let h = clamp(((p - a).x * ab.x + (p - a).y * ab.y) / denom, 0.0'f32, 1.0'f32)
  vectorLength(p - (a + ab * h))

proc distanceToLinePx(p, a, b: Vec2): float32 =
  distanceToLine(p.scaled(), a.scaled(), b.scaled())

func bezierQuadraticSpan(
    controls: openArray[Vec2], t0, t2: float32
): DrawableQuadraticSpan =
  let
    tm = (t0 + t2) * 0.5'f32
    p0 = bezierPoint(controls, t0)
    pm = bezierPoint(controls, tm)
    p2 = bezierPoint(controls, t2)
    p1 = pm * 2.0'f32 - (p0 + p2) * 0.5'f32
  DrawableQuadraticSpan(p0: p0, p1: p1, p2: p2)

func bezierQuadraticSpan(
    controls: openArray[Vec2], step, steps: int
): DrawableQuadraticSpan =
  bezierQuadraticSpan(
    controls, step.float32 / steps.float32, (step + 1).float32 / steps.float32
  )

proc quadraticApproxErrorPx(
    controls: openArray[Vec2], span: DrawableQuadraticSpan, t0, t2: float32
): float32 =
  for localT in [0.25'f32, 0.75'f32]:
    let
      t = t0 + (t2 - t0) * localT
      actual = bezierPoint(controls, t)
      approx = quadraticPoint(span.p0, span.p1, span.p2, localT)
    result = max(result, pointDistancePx(actual, approx))

proc appendAdaptiveBezierSpan(
    controls: openArray[Vec2],
    t0, t2: float32,
    depth: int,
    spans: var seq[DrawableQuadraticSpan],
) =
  let span = bezierQuadraticSpan(controls, t0, t2)
  let error = quadraticApproxErrorPx(controls, span, t0, t2)
  if error <= DrawableAdaptiveTolerancePx or depth >= MaxAdaptiveCurveDepth or
      spans.len >= MaxAdaptiveDrawableSteps - 1:
    spans.add span
  else:
    let tm = (t0 + t2) * 0.5'f32
    appendAdaptiveBezierSpan(controls, t0, tm, depth + 1, spans)
    appendAdaptiveBezierSpan(controls, tm, t2, depth + 1, spans)

proc adaptiveBezierSpans(controls: openArray[Vec2]): seq[DrawableQuadraticSpan] =
  appendAdaptiveBezierSpan(controls, 0.0'f32, 1.0'f32, 0, result)

proc fixedBezierSpans(
    controls: openArray[Vec2], steps: int
): seq[DrawableQuadraticSpan] =
  for step in 0 ..< steps:
    result.add bezierQuadraticSpan(controls, step, steps)

proc appendAdaptiveBezierSegmentPoint(
    controls: openArray[Vec2], t0, t2: float32, depth: int, points: var seq[Vec2]
) =
  let
    p0 = bezierPoint(controls, t0)
    p2 = bezierPoint(controls, t2)
    tm = (t0 + t2) * 0.5'f32
    pm = bezierPoint(controls, tm)
    error = distanceToLinePx(pm, p0, p2)
  if error <= DrawableAdaptiveTolerancePx or depth >= MaxAdaptiveCurveDepth or
      points.len >= MaxAdaptiveDrawableSteps:
    points.add p2
  else:
    appendAdaptiveBezierSegmentPoint(controls, t0, tm, depth + 1, points)
    appendAdaptiveBezierSegmentPoint(controls, tm, t2, depth + 1, points)

proc bezierSegmentPoints(controls: openArray[Vec2], fixedSteps: int): seq[Vec2] =
  result.add bezierPoint(controls, 0.0'f32)
  if fixedSteps > 0:
    for step in 1 .. fixedSteps:
      result.add bezierPoint(controls, step.float32 / fixedSteps.float32)
  else:
    appendAdaptiveBezierSegmentPoint(controls, 0.0'f32, 1.0'f32, 0, result)

proc adaptiveArcStepCount(radius, sweepAngle: float32): int =
  let
    radiusPx = max(0.0'f32, radius.scaled())
    absSweep = abs(sweepAngle)
  if radiusPx <= 0.0'f32 or absSweep <= 0.0'f32:
    return 1

  let
    cosLimit =
      clamp(1.0'f32 - DrawableAdaptiveTolerancePx / radiusPx, -1.0'f32, 1.0'f32)
    maxAngle = max(0.01'f32, 2.0'f32 * arccos(cosLimit))
  clamp(ceil(absSweep / maxAngle).int, 1, MaxAdaptiveDrawableSteps)

proc arcStepCount(op: DrawableOp, nodeSteps: uint16): int =
  let explicit = explicitDrawableStepCount(op.arcSteps, nodeSteps)
  if explicit > 0:
    explicit
  else:
    adaptiveArcStepCount(op.arcRadius, op.sweepAngle)

proc renderDrawableQuadraticBezierSdf(
    ctx: BackendContext,
    origin: Vec2,
    p0, p1, p2: Vec2,
    stroke: RenderStroke,
    cap: StrokeCap = scAuto,
) =
  let resolvedCap =
    if cap == scAuto:
      stroke.resolveCurveCap()
    else:
      cap
  if isFlatQuadratic(p0, p1, p2):
    ctx.renderDrawableLine(origin, drawableLine(p0, p2), stroke.withCap(resolvedCap))
    return

  let
    strokeWeight = max(0.0'f32, stroke.weight)
    padding = strokeWeight * 0.5'f32 + drawableSdfPadding()
    a = origin + p0
    b = origin + p1
    c = origin + p2
    box = quadraticBounds(a, b, c, padding)
  if box.w <= 0.0'f32 or box.h <= 0.0'f32:
    return

  let
    center = box.xy + box.wh * 0.5'f32
    localA = (a - center).scaled()
    localB = (b - center).scaled()
    localC = (c - center).scaled()
  ctx.drawQuadraticBezierSdf(
    rect = box.scaled(),
    fill = stroke.fill.toBackendFill(),
    p0 = localA,
    p1 = localB,
    p2 = localC,
    strokeWeight = strokeWeight.scaled(),
    cap = resolvedCap,
  )

proc renderDrawableBezierSegments(
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

  let
    fixedSteps = explicitDrawableStepCount(op.steps, nodeSteps)
    points = bezierSegmentPoints(op.controls, fixedSteps)
  if points.len < 2:
    return

  let
    cap = stroke.resolveCurveCap()
    join = stroke.resolveCurveJoin()
    capRadius = max(0.0'f32, stroke.weight) / 2.0'f32
    segmentStroke = stroke.withCap(scButt)
  var previous = points[0]
  var previousTangent = vec2(1.0'f32, 0.0'f32)
  for step in 1 ..< points.len:
    let
      current = points[step]
      segment = drawableLine(previous, current)
      tangent = current - previous
    ctx.renderDrawableLine(origin, segment, segmentStroke)
    if step == 1:
      ctx.renderDrawableEndpointCap(
        origin, previous, tangent, capRadius, stroke, cap, isStart = true
      )
    else:
      ctx.renderDrawableStrokeJoin(
        origin, previous, previousTangent, tangent, capRadius, stroke.fill, join
      )
    if step == points.len - 1:
      ctx.renderDrawableEndpointCap(
        origin, current, tangent, capRadius, stroke, cap, isStart = false
      )
    previous = current
    previousTangent = tangent

proc renderDrawableBezierQuadratics(
    ctx: BackendContext,
    origin: Vec2,
    op: DrawableOp,
    stroke: RenderStroke,
    nodeSteps: uint16,
) =
  let fixedSteps = explicitDrawableStepCount(op.steps, nodeSteps)
  let spans =
    if fixedSteps > 0:
      fixedBezierSpans(op.controls, fixedSteps)
    else:
      adaptiveBezierSpans(op.controls)
  let
    cap = stroke.resolveCurveCap()
    join = stroke.resolveCurveJoin()
    simpleRoundSpans = cap == scRound and join == sjRound
    spanCap = if simpleRoundSpans: scRound else: scButt
    capRadius = max(0.0'f32, stroke.weight) / 2.0'f32
  var previousSpan: DrawableQuadraticSpan
  for step, span in spans:
    ctx.renderDrawableQuadraticBezierSdf(
      origin, span.p0, span.p1, span.p2, stroke, spanCap
    )
    if not simpleRoundSpans:
      if step == 0:
        ctx.renderDrawableEndpointCap(
          origin, span.p0, span.startTangent(), capRadius, stroke, cap, isStart = true
        )
      else:
        ctx.renderDrawableStrokeJoin(
          origin,
          span.p0,
          previousSpan.endTangent(),
          span.startTangent(),
          capRadius,
          stroke.fill,
          join,
        )
      if step == spans.len - 1:
        ctx.renderDrawableEndpointCap(
          origin, span.p2, span.endTangent(), capRadius, stroke, cap, isStart = false
        )
    previousSpan = span

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

  when not defined(useFigDrawTextures):
    if op.controls.len == 3:
      ctx.renderDrawableQuadraticBezierSdf(
        origin,
        op.controls[0],
        op.controls[1],
        op.controls[2],
        stroke,
        stroke.resolveCurveCap(),
      )
      return
    if op.controls.len > 3:
      ctx.renderDrawableBezierQuadratics(origin, op, stroke, nodeSteps)
      return

  ctx.renderDrawableBezierSegments(origin, op, stroke, nodeSteps)

func arcPoint(center: Vec2, radius, angle: float32): Vec2 =
  center + vec2(cos(angle) * radius, sin(angle) * radius)

when defined(useFigDrawTextures):
  proc renderDrawableArcSegments(
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
    let
      cap = stroke.resolveCurveCap()
      join = stroke.resolveCurveJoin()
      capRadius = max(0.0'f32, stroke.weight) / 2.0'f32
      segmentStroke = stroke.withCap(scButt)
    var previous = arcPoint(op.arcCenter, radius, op.startAngle)
    var previousTangent = vec2(1.0'f32, 0.0'f32)
    for step in 1 .. steps:
      let
        t = step.float32 / steps.float32
        angle = op.startAngle + op.sweepAngle * t
        current = arcPoint(op.arcCenter, radius, angle)
        segment = drawableLine(previous, current)
        tangent = current - previous
      ctx.renderDrawableLine(origin, segment, segmentStroke)
      if step == 1:
        ctx.renderDrawableEndpointCap(
          origin, previous, tangent, capRadius, stroke, cap, isStart = true
        )
      else:
        ctx.renderDrawableStrokeJoin(
          origin, previous, previousTangent, tangent, capRadius, stroke.fill, join
        )
      if step == steps:
        ctx.renderDrawableEndpointCap(
          origin, current, tangent, capRadius, stroke, cap, isStart = false
        )
      previous = current
      previousTangent = tangent

when not defined(useFigDrawTextures):
  func arcQuadraticSpan(
      op: DrawableOp, step, steps: int, radius: float32
  ): DrawableQuadraticSpan =
    let
      t0 = step.float32 / steps.float32
      t2 = (step + 1).float32 / steps.float32
      tm = (t0 + t2) * 0.5'f32
      angle0 = op.startAngle + op.sweepAngle * t0
      angle2 = op.startAngle + op.sweepAngle * t2
      angleMid = op.startAngle + op.sweepAngle * tm
      p0 = arcPoint(op.arcCenter, radius, angle0)
      pm = arcPoint(op.arcCenter, radius, angleMid)
      p2 = arcPoint(op.arcCenter, radius, angle2)
      p1 = pm * 2.0'f32 - (p0 + p2) * 0.5'f32
    DrawableQuadraticSpan(p0: p0, p1: p1, p2: p2)

  proc renderDrawableArcQuadratics(
      ctx: BackendContext,
      origin: Vec2,
      op: DrawableOp,
      stroke: RenderStroke,
      nodeSteps: uint16,
  ) =
    let
      radius = max(0.0'f32, op.arcRadius)
      steps = op.arcStepCount(nodeSteps)
      cap = stroke.resolveCurveCap()
      join = stroke.resolveCurveJoin()
      simpleRoundSpans = cap == scRound and join == sjRound
      spanCap = if simpleRoundSpans: scRound else: scButt
      capRadius = max(0.0'f32, stroke.weight) / 2.0'f32
    var previousSpan: DrawableQuadraticSpan
    for step in 0 ..< steps:
      let span = arcQuadraticSpan(op, step, steps, radius)
      ctx.renderDrawableQuadraticBezierSdf(
        origin, span.p0, span.p1, span.p2, stroke, spanCap
      )
      if not simpleRoundSpans:
        if step == 0:
          ctx.renderDrawableEndpointCap(
            origin, span.p0, span.startTangent(), capRadius, stroke, cap, isStart = true
          )
        else:
          ctx.renderDrawableStrokeJoin(
            origin,
            span.p0,
            previousSpan.endTangent(),
            span.startTangent(),
            capRadius,
            stroke.fill,
            join,
          )
        if step == steps - 1:
          ctx.renderDrawableEndpointCap(
            origin, span.p2, span.endTangent(), capRadius, stroke, cap, isStart = false
          )
      previousSpan = span

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

  when not defined(useFigDrawTextures):
    ctx.renderDrawableArcQuadratics(origin, op, stroke, nodeSteps)
  else:
    ctx.renderDrawableArcSegments(origin, op, stroke, nodeSteps)

proc renderDrawableOps(ctx: BackendContext, node: Fig) =
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

proc renderDrawable*(ctx: BackendContext, node: Fig) =
  if node.drawAa <= 0.0'f32:
    ctx.renderDrawableOps(node)
    return

  let oldAa = ctx.sdfAaFactor()
  if oldAa == node.drawAa:
    ctx.renderDrawableOps(node)
    return

  ctx.setSdfAaFactor(node.drawAa)
  try:
    ctx.renderDrawableOps(node)
  finally:
    ctx.setSdfAaFactor(oldAa)

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

proc processImageMessages*(ctx: BackendContext) {.forbids: [AppMainThreadEff].} =
  ctx.ensureImageMessageSubscription()
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
  while tryRecvImageMsg(ctx.imageMessages, img):
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
      clearGlyphRasterFontCache(img.fontId)
      ctx.clearFontGlyphs(img.fontId)
    of ImkClearTypefaceGlyphs:
      trace "typeface glyphs cleared", typefaceId = $Hash(img.typefaceId)
      clearGlyphRasterTypefaceCache(img.typefaceId)
      ctx.clearTypefaceGlyphs(img.typefaceId)
    of ImkRetainImage:
      trace "image retained", id = $img.id.Hash
      ctx.retainImageOwner(img.id, img.ownerToken)
    of ImkReleaseImage:
      trace "image released", id = $img.id.Hash
      discard ctx.releaseImageOwner(img.id, img.ownerToken)
      if img.finalRelease:
        ctx.removeImage(img.id)
    of ImkRetainFont:
      trace "font retained", fontId = $Hash(img.fontId)
      ctx.retainFontOwner(img.fontId, img.ownerToken)
    of ImkReleaseFont:
      trace "font released", fontId = $Hash(img.fontId)
      discard ctx.releaseFontOwner(img.fontId, img.ownerToken)
      if img.finalRelease:
        clearGlyphRasterFontCache(img.fontId)
        ctx.clearFontGlyphs(img.fontId)

proc renderRoot*(
    ctx: BackendContext, nodes: var Renders
) {.forbids: [AppMainThreadEff].} =
  ## draw roots for each level
  ctx.processImageMessages()
  for zlvl, list in nodes.layers.pairs():
    for rootIdx in list.rootIds:
      ctx.render(list.nodes, rootIdx, -1.FigIdx)

  ctx.publishAtlasUsage()

proc processImageMessages*[BackendState](renderer: FigRenderer[BackendState]) =
  renderer.ctx.processImageMessages()

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
