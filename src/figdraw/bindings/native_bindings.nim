## Native Nim dynamic-library facade generated through Binny.

import std/tables

import chroma
import vmath

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender
import figdraw/common/[fonttypes, fontutils]
import figdraw/windowing/siwinshim

type
  NativeWindowSize* = object
    w*, h*: int32

  NativeRenders* = object
    raw*: pointer

  NativeTypeface* = object
    raw*: pointer

  NativeFigFont* = object
    raw*: pointer

  NativeGlyphLayout* = object
    raw*: pointer

  NativeSiwinApp* = object
    raw*: pointer

  TypefaceBox = ref object
    value: TypefaceId

  FontBox = ref object
    value: FigFont

  LayoutBox = ref object
    value: GlyphArrangement

  SiwinApp = ref object
    window: Window
    renderer: FigRenderer[SiwinRenderBackend]
    autoScale: bool

proc retainRaw[T](raw: pointer) =
  if raw != nil:
    let value {.cursor.} = cast[T](raw)
    GC_ref(value)

proc releaseRaw[T](raw: pointer) =
  if raw != nil:
    let value {.cursor.} = cast[T](raw)
    GC_unref(value)

template defineHandleHooks(HandleType, RefType: typedesc) =
  proc `=destroy`(value: HandleType) =
    releaseRaw[RefType](value.raw)

  proc `=copy`(dest: var HandleType, source: HandleType) =
    if dest.raw != source.raw:
      retainRaw[RefType](source.raw)
      releaseRaw[RefType](dest.raw)
      dest.raw = source.raw

defineHandleHooks(NativeRenders, Renders)
defineHandleHooks(NativeTypeface, TypefaceBox)
defineHandleHooks(NativeFigFont, FontBox)
defineHandleHooks(NativeGlyphLayout, LayoutBox)
defineHandleHooks(NativeSiwinApp, SiwinApp)

proc wrap(value: Renders): NativeRenders =
  retainRaw[Renders](cast[pointer](value))
  result.raw = cast[pointer](value)

proc wrap(value: TypefaceBox): NativeTypeface =
  retainRaw[TypefaceBox](cast[pointer](value))
  result.raw = cast[pointer](value)

proc wrap(value: FontBox): NativeFigFont =
  retainRaw[FontBox](cast[pointer](value))
  result.raw = cast[pointer](value)

proc wrap(value: LayoutBox): NativeGlyphLayout =
  retainRaw[LayoutBox](cast[pointer](value))
  result.raw = cast[pointer](value)

proc wrap(value: SiwinApp): NativeSiwinApp =
  retainRaw[SiwinApp](cast[pointer](value))
  result.raw = cast[pointer](value)

template renders(value: NativeRenders): Renders =
  cast[Renders](value.raw)

template typeface(value: NativeTypeface): TypefaceBox =
  cast[TypefaceBox](value.raw)

template font(value: NativeFigFont): FontBox =
  cast[FontBox](value.raw)

template layout(value: NativeGlyphLayout): LayoutBox =
  cast[LayoutBox](value.raw)

template siwinApp(value: NativeSiwinApp): SiwinApp =
  cast[SiwinApp](value.raw)

proc isNil*(value: NativeRenders): bool {.exportabi.} =
  value.raw == nil

proc isNil*(value: NativeTypeface): bool {.exportabi.} =
  value.raw == nil

proc isNil*(value: NativeFigFont): bool {.exportabi.} =
  value.raw == nil

proc isNil*(value: NativeGlyphLayout): bool {.exportabi.} =
  value.raw == nil

proc isNil*(value: NativeSiwinApp): bool {.exportabi.} =
  value.raw == nil

proc nativeNewTextFig*(x, y, w, h: float32): Fig {.exportabi.} =
  Fig(
    kind: nkText,
    screenBox: rect(x, y, w, h),
    fill: fill(rgba(255, 255, 255, 255)),
    textLayout: GlyphArrangement(),
  )

proc nativeNewRenders*(): NativeRenders {.exportabi.} =
  wrap(Renders(layers: initOrderedTable[ZLevel, RenderList]()))

proc nativeClearRenders*(rendersHandle: NativeRenders) {.exportabi.} =
  renders(rendersHandle).layers.clear()

proc nativeAddRoot*(
    rendersHandle: NativeRenders, zLevel: int8, root: Fig
): int16 {.exportabi.} =
  var nodes = renders(rendersHandle)
  cast[int16](nodes.addRoot(ZLevel(zLevel), root))

proc nativeLayerNodeCount*(
    rendersHandle: NativeRenders, zLevel: int8
): int {.exportabi.} =
  let nodes = renders(rendersHandle)
  let level = ZLevel(zLevel)
  if level in nodes.layers:
    nodes.layers[level].nodes.len
  else:
    0

proc nativeLoadTypeface*(name: string): NativeTypeface {.exportabi.} =
  wrap(TypefaceBox(value: loadTypeface(name)))

proc nativeNewFigFont*(
    typefaceHandle: NativeTypeface, size: float32
): NativeFigFont {.exportabi.} =
  wrap(FontBox(value: FigFont(typefaceId: typeface(typefaceHandle).value, size: size)))

proc nativeTypesetText*(
    width, height: float32,
    fontHandle: NativeFigFont,
    text: string,
    hAlign: int8 = 0,
    vAlign: int8 = 0,
    minContent = false,
    wrapText = false,
): NativeGlyphLayout {.exportabi.} =
  let
    horizontal =
      case hAlign
      of 1: Center
      of 2: Right
      else: Left
    vertical =
      case vAlign
      of 1: Middle
      of 2: Bottom
      else: Top
    arrangement = typeset(
      rect(0, 0, width, height),
      [(font(fontHandle).value, text)],
      horizontal,
      vertical,
      minContent,
      wrapText,
    )
  wrap(LayoutBox(value: arrangement))

proc nativeSetFigTextLayout*(
    node: var Fig, layoutHandle: NativeGlyphLayout
) {.exportabi.} =
  node.textLayout = layout(layoutHandle).value

proc nativeNewFigSiwinApp*(
    width, height: int32,
    title: string,
    atlasSize: int,
    pixelScale: float32,
    fullscreen, vsync: bool,
    msaa: int32,
    resizable, frameless, transparent: bool,
): NativeSiwinApp {.exportabi.} =
  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize, SiwinRenderBackend(), pixelScale)
    let window = newSiwinWindow(
      renderer,
      ivec2(width, height),
      fullscreen,
      title,
      vsync,
      msaa,
      resizable,
      frameless,
      transparent,
    )
  else:
    let window = newSiwinWindow(
      ivec2(width, height),
      fullscreen,
      title,
      vsync,
      msaa,
      resizable,
      frameless,
      transparent,
    )
    let renderer =
      newFigRenderer(atlasSize, SiwinRenderBackend(window: window), pixelScale)
  renderer.setupBackend(window)
  wrap(
    SiwinApp(window: window, renderer: renderer, autoScale: window.configureUiScale())
  )

proc nativeSiwinFirstStep*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.firstStep()

proc nativeSiwinStep*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.step()

proc nativeSiwinRedraw*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.redraw()

proc nativeSiwinClose*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.close()

proc nativeSiwinOpened*(appHandle: NativeSiwinApp): bool {.exportabi.} =
  siwinApp(appHandle).window.opened

proc nativeSiwinWindowSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
  let size = siwinApp(appHandle).window.size
  NativeWindowSize(w: size.x, h: size.y)

proc nativeSiwinRefreshUiScale*(appHandle: NativeSiwinApp) {.exportabi.} =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)

proc nativeSiwinBackendName*(appHandle: NativeSiwinApp): string {.exportabi.} =
  siwinApp(appHandle).renderer.siwinBackendName()

proc nativeSiwinDisplayServerName*(appHandle: NativeSiwinApp): string {.exportabi.} =
  siwinApp(appHandle).window.siwinDisplayServerName()

proc nativeRenderSiwinFrame*(
    appHandle: NativeSiwinApp, rendersHandle: NativeRenders, width, height: float32
) {.exportabi.} =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  var nodes = renders(rendersHandle)
  app.renderer.renderFrame(nodes, vec2(width, height))
  app.renderer.endFrame()

proc nativeRenderSiwinFrame*(
    appHandle: NativeSiwinApp, rendersHandle: NativeRenders
) {.exportabi.} =
  let size = siwinApp(appHandle).window.backingSize()
  nativeRenderSiwinFrame(appHandle, rendersHandle, size.x.float32, size.y.float32)

proc nativeSetFigDataDir*(path: string) {.exportabi.} =
  setFigDataDir(path)
