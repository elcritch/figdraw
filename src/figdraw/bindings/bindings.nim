import genny
import std/tables
import std/hashes
import vmath
import std/os
import figdraw/commons
import figdraw/fignodes as fdn
import figdraw/figrender as fgr
import figdraw/common/fonttypes as fnt
from figdraw/fignodes import Renders
from figdraw/common/fonttypes import FontCase
from figdraw/common/shared import FigDrawError
import figdraw/common/fontutils as fut
when not defined(emscripten):
  import figdraw/utils/glutils

const ExportSiwinShim* {.booldefine: "figdraw.bindings.siwinshim".} = true
const GeneratedDir = currentSourcePath().parentDir / "generated"

when ExportSiwinShim and not defined(emscripten):
  import figdraw/windowing/siwinshim as siwinshim

var lastError: ref FigDrawError

proc raiseFigDrawError(e: ref Exception) {.raises: [FigDrawError].} =
  if e.isNil:
    raise newException(FigDrawError, "Unknown FigDraw binding error")
  raise newException(FigDrawError, e.msg, e)

proc takeError(): string =
  if lastError.isNil:
    return ""
  result = lastError.msg
  lastError = nil

proc checkError(): bool =
  result = lastError != nil

template returnIfNil(value: untyped) =
  if value.isNil:
    return

template withFigDrawError(body: untyped) =
  try:
    body
  except Exception as e:
    raiseFigDrawError(e)

type
  CornerRadii* = object
    values*: array[DirectionCorners, uint16]

  ScreenBox* = object
    x*, y*, w*, h*: float32

  WindowSize* = object
    w*, h*: int32

  FigRef* = ref object
    inner: fdn.Fig

  FigRendererRef* = ref object
    inner: fgr.FigRenderer[fgr.NoRendererBackendState]

  TypefaceRef* = ref object
    id: fnt.TypefaceId

  FigFontRef* = ref object
    inner: fnt.FigFont

  GlyphLayoutRef* = ref object
    inner: fnt.GlyphArrangement

when ExportSiwinShim and not defined(emscripten):
  type
    FigSiwinAppRef* = ref object
      window: siwinshim.Window
      renderer: fgr.FigRenderer[siwinshim.SiwinRenderBackend]
      autoScale: bool

proc newFig(): FigRef =
  FigRef(inner: fdn.Fig(kind: fdn.nkFrame))

proc initRgba(r, g, b, a: uint8): ColorRGBA =
  rgba(r, g, b, a)

proc cornerRadii(topLeft, topRight, bottomLeft, bottomRight: float32): CornerRadii =
  CornerRadii(values: [topLeft, topRight, bottomLeft, bottomRight])

func toFigKind(kind: int8): fdn.FigKind =
  let raw = kind.int
  if raw < ord(low(fdn.FigKind)) or raw > ord(high(fdn.FigKind)):
    fdn.nkFrame
  else:
    fdn.FigKind(raw)

proc newRectangleFig(x, y, w, h: float32): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkRectangle,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
    )
  )

proc newTextFig(x, y, w, h: float32): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkText,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      textLayout: GlyphArrangement(),
    )
  )

proc newImageFig(x, y, w, h: float32, imageId: int64): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkImage,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      image: ImageStyle(
        id: cast[ImageId](Hash(imageId)), fill: fill(rgba(255, 255, 255, 255))
      ),
    )
  )

proc newTransformFig(x, y, w, h: float32, tx, ty: float32): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkTransform,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      transform: TransformStyle(translation: vec2(tx, ty), useMatrix: false),
    )
  )

proc loadTypefaceBinding(name: string): TypefaceRef {.raises: [FigDrawError].} =
  withFigDrawError:
    let fontId = fut.loadTypeface(name)
    result = TypefaceRef(id: cast[fnt.TypefaceId](fontId))

proc newFigFontBinding(typeface: TypefaceRef, size: float32): FigFontRef =
  if typeface.isNil:
    return nil
  FigFontRef(inner: fnt.FigFont(typefaceId: typeface.id, size: size))

proc setFigFontLineHeightBinding(font: FigFontRef, lineHeight: float32) =
  returnIfNil font
  font.inner.lineHeight = lineHeight

proc setFigFontCaseBinding(font: FigFontRef, fontCase: FontCase) =
  returnIfNil font
  font.inner.fontCase = fontCase

proc typesetTextBinding(
    width, height: float32,
    font: FigFontRef,
    text: string,
    hAlign: int8 = 0,
    vAlign: int8 = 0,
    minContent = false,
    wrap = false,
): GlyphLayoutRef {.raises: [FigDrawError].} =
  if font.isNil:
    return nil
  var h = fnt.FontHorizontal.Left
  case hAlign
  of 1'i8:
    h = fnt.FontHorizontal.Center
  of 2'i8:
    h = fnt.FontHorizontal.Right
  else:
    discard

  var v = fnt.FontVertical.Top
  case vAlign
  of 1'i8:
    v = fnt.FontVertical.Middle
  of 2'i8:
    v = fnt.FontVertical.Bottom
  else:
    discard

  try:
    let layout = fut.typeset(
      box = rect(0'f32, 0'f32, width, height),
      uiSpans = @[(font.inner, text)],
      hAlign = h,
      vAlign = v,
      minContent = minContent,
      wrap = wrap,
    )
    result = GlyphLayoutRef(inner: layout)
  except Exception as e:
    raiseFigDrawError(e)

proc figWithKind(src: fdn.Fig, kind: fdn.FigKind): fdn.Fig {.raises: [].}

proc setFigTextLayoutBinding(fig: FigRef, layout: GlyphLayoutRef) {.raises: [FigDrawError].} =
  if fig.isNil or layout.isNil:
    return
  withFigDrawError:
    if fig.inner.kind != fdn.nkText:
      fig.inner = figWithKind(fig.inner, fdn.nkText)
    fig.inner.textLayout = layout.inner

proc textLayoutWidthBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.w

proc textLayoutHeightBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.h

proc copy(fig: FigRef): FigRef =
  if fig.isNil:
    return nil
  FigRef(inner: fig.inner)

proc figWithKind(src: fdn.Fig, kind: fdn.FigKind): fdn.Fig {.raises: [].} =
  result = fdn.Fig(kind: kind)
  result.zlevel = src.zlevel
  result.parent = src.parent
  result.flags = src.flags
  result.childCount = src.childCount
  result.screenBox = src.screenBox
  result.rotation = src.rotation
  result.fill = src.fill
  result.corners = src.corners

proc ensureRectangle(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)

proc kind(fig: FigRef): int8 =
  if fig.isNil:
    return fdn.nkFrame.int8
  fig.inner.kind.int8

proc setKind(fig: FigRef, kind: int8) =
  returnIfNil fig
  fig.inner = figWithKind(fig.inner, kind.toFigKind())

proc zLevel(fig: FigRef): int8 =
  if fig.isNil:
    return 0'i8
  fig.inner.zlevel.int8

proc setZLevel(fig: FigRef, zLevel: int8) =
  returnIfNil fig
  fig.inner.zlevel = fdn.ZLevel(zLevel)

proc getScreenBox(fig: FigRef): ScreenBox =
  if fig.isNil:
    return ScreenBox()
  ScreenBox(
    x: fig.inner.screenBox.x,
    y: fig.inner.screenBox.y,
    w: fig.inner.screenBox.w,
    h: fig.inner.screenBox.h,
  )

proc setScreenBox(fig: FigRef, x, y, w, h: float32) =
  returnIfNil fig
  fig.inner.screenBox = rect(x, y, w, h)

proc setFillColor(fig: FigRef, r, g, b, a: uint8) =
  returnIfNil fig
  fig.inner.fill = fill(rgba(r, g, b, a))

proc setFillColorRgba(fig: FigRef, color: ColorRGBA) =
  returnIfNil fig
  fig.inner.fill = fill(color)

proc setFillLinear2(fig: FigRef, startColor, endColor: ColorRGBA, axis: FillGradientAxis) =
  returnIfNil fig
  fig.inner.fill = linear(
    startColor,
    endColor,
    axis = axis,
  )

proc setFillLinear3(
    fig: FigRef,
    startColor, midColor, endColor: ColorRGBA,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  returnIfNil fig
  fig.inner.fill = linear(
    startColor,
    midColor,
    endColor,
    axis = axis,
    midPos = midPos,
  )

proc setRotation(fig: FigRef, rotation: float32) =
  returnIfNil fig
  fig.inner.rotation = rotation

proc setCorners(fig: FigRef, radii: CornerRadii) =
  returnIfNil fig
  fig.inner.corners = radii.values

proc setStroke(fig: FigRef, weight: float32, color: ColorRGBA) =
  returnIfNil fig
  fig.ensureRectangle()
  fig.inner.stroke = RenderStroke(weight: weight, fill: fill(color))

proc clearShadows(fig: FigRef) =
  returnIfNil fig
  fig.ensureRectangle()
  fig.inner.shadows = [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()]

proc setShadow(
    fig: FigRef,
    shadowIndex: int8,
    style: ShadowStyle,
    blur, spread, x, y: float32,
    color: ColorRGBA,
) =
  returnIfNil fig
  fig.ensureRectangle()
  if shadowIndex < 0'i8 or shadowIndex >= ShadowCount.int8:
    return

  fig.inner.shadows[shadowIndex.int] = RenderShadow(
    style: style,
    blur: blur,
    spread: spread,
    x: x,
    y: y,
    fill: fill(color),
  )

proc newRenders(): Renders =
  Renders(layers: initOrderedTable[fdn.ZLevel, fdn.RenderList]())

proc ensureOpenGLInitialized() =
  when not defined(emscripten):
    startOpenGL(openglVersion)

proc newFigRendererBinding*(atlasSize: int, pixelScale: float32): FigRendererRef {.raises: [FigDrawError].} =
  withFigDrawError:
    ensureOpenGLInitialized()
    result = FigRendererRef(inner: fgr.newFigRenderer(atlasSize, pixelScale))

proc renderFrameBinding*(renderer: FigRendererRef, renders: Renders, width, height: float32) {.raises: [FigDrawError].} =
  if renderer.isNil or renders.isNil:
    return
  withFigDrawError:
    var nodes = renders
    renderer.inner.renderFrame(nodes, vec2(width, height))

when ExportSiwinShim and not defined(emscripten):
  proc newFigSiwinAppBinding*(
      width, height: int32,
      title: string,
      atlasSize: int,
      pixelScale: float32,
      fullscreen: bool,
      vsync: bool,
      msaa: int32,
      resizable: bool,
      frameless: bool,
      transparent: bool,
  ): FigSiwinAppRef {.raises: [FigDrawError].} =
    withFigDrawError:
      when UseVulkanBackend:
        let renderer =
          fgr.newFigRenderer(atlasSize, siwinshim.SiwinRenderBackend(), pixelScale)
        let window = siwinshim.newSiwinWindow(
          renderer,
          ivec2(width, height),
          fullscreen = fullscreen,
          title = title,
          vsync = vsync,
          msaa = msaa,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
        renderer.setupBackend(window)
        result = FigSiwinAppRef(window: window, renderer: renderer)
      else:
        let window = siwinshim.newSiwinWindow(
          ivec2(width, height),
          fullscreen = fullscreen,
          title = title,
          vsync = vsync,
          msaa = msaa,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
        let renderer = fgr.newFigRenderer(
          atlasSize, siwinshim.SiwinRenderBackend(window: window), pixelScale
        )
        renderer.setupBackend(window)
        result = FigSiwinAppRef(window: window, renderer: renderer)
      result.autoScale = result.window.configureUiScale()

  proc siwinFirstStep(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.firstStep()

  proc siwinStep(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.step()

  proc siwinRedraw(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.redraw()

  proc siwinClose(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.close()

  proc siwinOpened(app: FigSiwinAppRef): bool {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return false
    withFigDrawError:
      result = app.window.opened

  proc siwinWindowSize(app: FigSiwinAppRef): WindowSize {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return WindowSize()
    withFigDrawError:
      let size = app.window.size
      result = WindowSize(w: size.x, h: size.y)

  proc siwinBackingSize(app: FigSiwinAppRef): WindowSize {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return WindowSize()
    withFigDrawError:
      let size = app.window.backingSize()
      result = WindowSize(w: size.x, h: size.y)

  proc siwinContentScale(app: FigSiwinAppRef): float32 {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return 1.0'f32
    withFigDrawError:
      result = app.window.contentScale()

  proc siwinRefreshUiScale(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.refreshUiScale(app.autoScale)

  proc siwinBackendName(app: FigSiwinAppRef): string {.raises: [FigDrawError].} =
    if app.isNil or app.renderer.isNil:
      return ""
    withFigDrawError:
      result = app.renderer.siwinBackendName()

  proc siwinDisplayServerName(app: FigSiwinAppRef): string {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return ""
    withFigDrawError:
      result = app.window.siwinDisplayServerName()

  proc renderSiwinFrameBinding*(
      app: FigSiwinAppRef, renders: Renders, width, height: float32
  ) {.raises: [FigDrawError].} =
    if app.isNil or app.renderer.isNil or renders.isNil:
      return
    withFigDrawError:
      app.window.refreshUiScale(app.autoScale)
      app.renderer.beginFrame()
      var nodes = renders
      app.renderer.renderFrame(nodes, vec2(width, height))
      app.renderer.endFrame()

  proc renderSiwinFrameBinding*(
      app: FigSiwinAppRef, renders: Renders
  ) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil or renders.isNil:
      return
    withFigDrawError:
      let size = app.window.backingSize()
      renderSiwinFrameBinding(app, renders, size.x.float32, size.y.float32)

proc clear(renders: Renders) =
  returnIfNil renders
  renders.layers.clear()

proc containsLayer(renders: Renders, zLevel: int8): bool =
  if renders.isNil:
    return false
  renders.contains(fdn.ZLevel(zLevel))

proc addRoot(renders: Renders, zLevel: int8, root: FigRef): int16 {.raises: [FigDrawError].} =
  if renders.isNil or root.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.addRoot(fdn.ZLevel(zLevel), root.inner).int16

proc insertRoot(
    renders: Renders, zLevel: int8, rootPos: int, root: FigRef
): int16 {.raises: [FigDrawError].} =
  if renders.isNil or root.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.insertRoot(fdn.ZLevel(zLevel), root.inner, rootPos.Natural).int16

proc addChild(renders: Renders, zLevel: int8, parentIdx: int16, child: FigRef): int16 {.raises: [FigDrawError].} =
  if renders.isNil or child.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.addChild(fdn.ZLevel(zLevel), fdn.FigIdx(parentIdx), child.inner).int16

proc insertChild(
    renders: Renders, zLevel: int8, parentIdx: int16, childPos: int, child: FigRef
): int16 {.raises: [FigDrawError].} =
  if renders.isNil or child.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.insertChild(
      fdn.ZLevel(zLevel), fdn.FigIdx(parentIdx), child.inner, childPos.Natural
    ).int16

proc layerNodeCount(renders: Renders, zLevel: int8): int {.raises: [FigDrawError].} =
  if renders.isNil:
    return 0
  try:
    if not renders.containsLayer(zLevel):
      return 0
    result = renders[fdn.ZLevel(zLevel)].nodes.len
  except Exception as e:
    raiseFigDrawError(e)

proc layerRootCount(renders: Renders, zLevel: int8): int {.raises: [FigDrawError].} =
  if renders.isNil:
    return 0
  try:
    if not renders.containsLayer(zLevel):
      return 0
    result = renders[fdn.ZLevel(zLevel)].rootIds.len
  except Exception as e:
    raiseFigDrawError(e)

proc getLayerNode(renders: Renders, zLevel: int8, nodeIdx: int16): FigRef {.raises: [FigDrawError].} =
  if renders.isNil:
    return nil
  try:
    result = FigRef(inner: renders[fdn.ZLevel(zLevel)].nodes[nodeIdx.int])
  except Exception as e:
    raiseFigDrawError(e)

exportProcs:
  checkError
  takeError

exportEnums:
  FillGradientAxis
  FontCase
  DirectionCorners
  ShadowStyle

exportObject chroma.ColorRGBA:
  constructor:
    initRgba(uint8, uint8, uint8, uint8)

exportObject CornerRadii:
  constructor:
    cornerRadii(float32, float32, float32, float32)

exportObject ScreenBox:
  discard

exportObject WindowSize:
  discard

exportRefObject FigRef:
  constructor:
    newFig()
  procs:
    copy(FigRef)
    kind(FigRef)
    setKind(FigRef, int8)
    zLevel(FigRef)
    setZLevel(FigRef, int8)
    getScreenBox(FigRef)
    setScreenBox(FigRef, float32, float32, float32, float32)
    setFillColor(FigRef, uint8, uint8, uint8, uint8)
    setFillColorRgba(FigRef, ColorRGBA)
    setFillLinear2(FigRef, ColorRGBA, ColorRGBA, FillGradientAxis)
    setFillLinear3(FigRef, ColorRGBA, ColorRGBA, ColorRGBA, FillGradientAxis, uint8)
    setRotation(FigRef, float32)
    setCorners(FigRef, CornerRadii)
    setStroke(FigRef, float32, ColorRGBA)
    clearShadows(FigRef)
    setShadow(FigRef, int8, ShadowStyle, float32, float32, float32, float32, ColorRGBA)

exportRefObject Renders:
  constructor:
    newRenders()
  procs:
    clear(Renders)
    containsLayer(Renders, int8)
    addRoot(Renders, int8, FigRef)
    insertRoot(Renders, int8, int, FigRef)
    addChild(Renders, int8, int16, FigRef)
    insertChild(Renders, int8, int16, int, FigRef)
    layerNodeCount(Renders, int8)
    layerRootCount(Renders, int8)
    getLayerNode(Renders, int8, int16)

exportRefObject FigRendererRef:
  constructor:
    newFigRendererBinding(int, float32)
  procs:
    renderFrameBinding(FigRendererRef, Renders, float32, float32)

when ExportSiwinShim and not defined(emscripten):
  exportRefObject FigSiwinAppRef:
    constructor:
      newFigSiwinAppBinding(
        int32, int32, string, int, float32, bool, bool, int32, bool, bool, bool
      )
    procs:
      siwinFirstStep(FigSiwinAppRef)
      siwinStep(FigSiwinAppRef)
      siwinRedraw(FigSiwinAppRef)
      siwinClose(FigSiwinAppRef)
      siwinOpened(FigSiwinAppRef)
      siwinWindowSize(FigSiwinAppRef)
      siwinBackingSize(FigSiwinAppRef)
      siwinContentScale(FigSiwinAppRef)
      siwinRefreshUiScale(FigSiwinAppRef)
      siwinBackendName(FigSiwinAppRef)
      siwinDisplayServerName(FigSiwinAppRef)
      renderSiwinFrameBinding(FigSiwinAppRef, Renders, float32, float32)
      renderSiwinFrameBinding(FigSiwinAppRef, Renders)

exportRefObject TypefaceRef:
  discard

exportRefObject FigFontRef:
  constructor:
    newFigFontBinding(TypefaceRef, float32)
  procs:
    setFigFontLineHeightBinding(FigFontRef, float32)
    setFigFontCaseBinding(FigFontRef, FontCase)

exportRefObject GlyphLayoutRef:
  procs:
    textLayoutWidthBinding(GlyphLayoutRef)
    textLayoutHeightBinding(GlyphLayoutRef)

exportProcs:
  newRectangleFig
  newTextFig
  newImageFig
  newTransformFig
  loadTypefaceBinding
  typesetTextBinding
  setFigTextLayoutBinding
  figDataDir
  setFigDataDir
  figUiScale
  setFigUiScale
  scaled(float32)
  descaled(float32)

writeFiles(GeneratedDir, "Figdraw")

include generated/internal
