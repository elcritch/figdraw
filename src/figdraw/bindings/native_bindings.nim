## Native Nim dynamic-library facade generated through Binny.

import vmath

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender
import figdraw/windowing/siwinshim

type
  NativeWindowSize* = object
    w*, h*: int32

  NativeSiwinApp* = object
    raw*: pointer

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

defineHandleHooks(NativeSiwinApp, SiwinApp)

proc wrap(value: SiwinApp): NativeSiwinApp =
  retainRaw[SiwinApp](cast[pointer](value))
  result.raw = cast[pointer](value)

template siwinApp(value: NativeSiwinApp): SiwinApp =
  cast[SiwinApp](value.raw)

proc isNil*(value: NativeSiwinApp): bool {.exportabi.} =
  value.raw == nil

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
    appHandle: NativeSiwinApp, renders: Renders, width, height: float32
) {.exportabi.} =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  var nodes = renders
  app.renderer.renderFrame(nodes, vec2(width, height))
  app.renderer.endFrame()

proc nativeRenderSiwinFrame*(
    appHandle: NativeSiwinApp, renders: Renders
) {.exportabi.} =
  let size = siwinApp(appHandle).window.backingSize()
  nativeRenderSiwinFrame(appHandle, renders, size.x.float32, size.y.float32)
