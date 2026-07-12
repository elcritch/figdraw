## Source-compatible FigDraw/Siwin facade backed by the native Nim dynamic library.

import std/tables
import figdraw_native_abi

export tables, figdraw_native_abi

const
  UseVulkanBackend* = false
  UseMetalBackend* = false

type
  ZLevel* = int8
  Color* = figdraw_native_abi.Fill
  ImageRef* = ImageId

  FontStyle* = object
    font*: FigFont
    color*: figdraw_native_abi.Fill

  IVec2* = object
    x*, y*: int32

  Vec2* = object
    x*, y*: float32

  SiwinRenderBackend* = object

  Window* = ref object
    handle: NativeSiwinApp
    eventsHandler*: WindowEventsHandler
    redrawRequested: bool
    lastSize: IVec2
    wasOpened: bool
    escapePressed: bool
    width, height: int32
    titleText: string
    fullscreen, vsync, resizable, frameless, transparent: bool

  FigRenderer*[BackendState] = ref object
    atlasSize: int
    pixelScale: float32
    window: Window

  CloseEvent* = object
    window*: Window

  RenderEvent* = object
    window*: Window

  ResizeEvent* = object
    window*: Window
    size*: IVec2
    initial*: bool

  KeyEvent* = object
    window*: Window
    key*: Key
    pressed*: bool
    repeated*: bool
    generated*: bool

  WindowEventsHandler* = object
    onClose*: proc(e: CloseEvent)
    onRender*: proc(e: RenderEvent)
    onResize*: proc(e: ResizeEvent)
    onKey*: proc(e: KeyEvent)

func ivec2*(x, y: int32): IVec2 =
  IVec2(x: x, y: y)

func vec2*(x, y: float32): Vec2 =
  Vec2(x: x, y: y)

func `==`*(a, b: Vec2): bool =
  a.x == b.x and a.y == b.y

func rect*(x, y, w, h: float32): Rect =
  Rect(x: x, y: y, w: w, h: h)

func rgba*(r, g, b: uint8, a: uint8 = 255): ColorRGBA =
  ColorRGBA(r: r, g: g, b: b, a: a)

proc color*(value: ColorRGBA): figdraw_native_abi.Fill =
  fill(value)

converter toFill*(value: ColorRGBA): figdraw_native_abi.Fill =
  fill(value)

let clearColor* = fill(rgba(0, 0, 0, 0))

proc fs*(font: FigFont, color: figdraw_native_abi.Fill = fill(rgba(0, 0, 0, 255))): FontStyle =
  FontStyle(font: font, color: color)

proc typeset*(
    box: Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement =
  if spans.len == 0:
    return GlyphArrangement()
  if spans.len > 1:
    raise
      newException(ValueError, "native dynlib typeset does not support multiple spans")
  figdraw_native_abi.typeset(
    box,
    spans[0][0].font,
    spans[0][0].color,
    spans[0][1],
    hAlign,
    vAlign,
    minContent,
    wrap,
  )

proc addRoot*(renders: Renders, lvl: ZLevel, root: Fig): FigIdx {.discardable.} =
  var mutableRenders = renders
  figdraw_native_abi.addRoot(mutableRenders, int8(lvl), root)

proc addRoot*(renders: Renders, root: Fig): FigIdx {.discardable.} =
  var mutableRenders = renders
  figdraw_native_abi.addRoot(mutableRenders, root)

proc loadImageRef*(filePath: string): ImageRef =
  loadFigImage(filePath)

proc imageStyle*(image: ImageRef): ImageStyle =
  ImageStyle(id: image, fill: fill(rgba(255, 255, 255, 255)))

proc newFigRenderer*(
    atlasSize: int, backendState: SiwinRenderBackend, pixelScale = 1.0'f32
): FigRenderer[SiwinRenderBackend] =
  discard backendState
  FigRenderer[SiwinRenderBackend](atlasSize: atlasSize, pixelScale: pixelScale)

proc newSiwinWindow*(
    size = ivec2(1280, 720),
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
    resizable = true,
    frameless = false,
    transparent = false,
): Window =
  discard msaa
  Window(
    width: size.x,
    height: size.y,
    titleText: title,
    fullscreen: fullscreen,
    vsync: vsync,
    resizable: resizable,
    frameless: frameless,
    transparent: transparent,
  )

proc setupBackend*(renderer: FigRenderer[SiwinRenderBackend], window: Window) =
  if window.handle.isNil:
    window.handle = newFigSiwinApp(
      window.width, window.height, window.titleText, renderer.atlasSize,
      renderer.pixelScale, window.fullscreen, window.vsync, 0, window.resizable,
      window.frameless, window.transparent,
    )
  renderer.window = window

proc newSiwinWindow*(
    renderer: FigRenderer[SiwinRenderBackend],
    size = ivec2(1280, 720),
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
    resizable = true,
    frameless = false,
    transparent = false,
): Window =
  result = newSiwinWindow(
    size, fullscreen, title, vsync, msaa, resizable, frameless, transparent
  )
  renderer.setupBackend(result)

proc configureUiScale*(window: Window): bool =
  discard window
  false

proc refreshUiScale*(window: Window, autoScale: bool) =
  discard autoScale
  siwinRefreshUiScale(window.handle)

proc contentScale*(window: Window): float32 =
  siwinUiScale(window.handle)

proc backingSize*(window: Window): IVec2 =
  let size = siwinWindowSize(window.handle)
  ivec2(size.w, size.h)

proc size*(window: Window): IVec2 =
  window.backingSize()

proc `size=`*(window: Window, value: IVec2) =
  siwinSetWindowSize(window.handle, value.x, value.y)

proc pos*(window: Window): IVec2 =
  let pos = siwinWindowPos(window.handle)
  ivec2(pos.x, pos.y)

proc `pos=`*(window: Window, value: IVec2) =
  siwinSetWindowPos(window.handle, value.x, value.y)

proc logicalSize*(window: Window): Vec2 =
  let
    size = window.backingSize()
    scale = max(window.contentScale(), 0.0001'f32)
  vec2(size.x.float32 / scale, size.y.float32 / scale)

proc `title=`*(window: Window, value: string) =
  window.titleText = value
  siwinSetTitle(window.handle, value)

proc opened*(window: Window): bool =
  not window.handle.isNil and opened(window.handle)

proc close*(window: Window) =
  if not window.handle.isNil:
    close(window.handle)

proc firstStep*(window: Window, makeVisible = true) =
  firstStep(window.handle, makeVisible)
  window.lastSize = window.backingSize()
  window.wasOpened = window.opened

proc redraw*(window: Window) =
  window.redrawRequested = true
  redraw(window.handle)

proc step*(window: Window) =
  let size = window.backingSize()
  if size.x != window.lastSize.x or size.y != window.lastSize.y:
    window.lastSize = size
    if window.eventsHandler.onResize != nil:
      window.eventsHandler.onResize(
        ResizeEvent(window: window, size: size, initial: false)
      )

  let escapePressed = siwinKeyPressed(window.handle, escape)
  if escapePressed != window.escapePressed and window.eventsHandler.onKey != nil:
    window.eventsHandler.onKey(
      KeyEvent(window: window, key: escape, pressed: escapePressed)
    )
  window.escapePressed = escapePressed

  if window.redrawRequested and window.eventsHandler.onRender != nil:
    window.redrawRequested = false
    window.eventsHandler.onRender(RenderEvent(window: window))

  step(window.handle)
  let isOpened = window.opened
  if window.wasOpened and not isOpened and window.eventsHandler.onClose != nil:
    window.eventsHandler.onClose(CloseEvent(window: window))
  window.wasOpened = isOpened

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  discard renderer

proc renderFrame*(renderer: FigRenderer[SiwinRenderBackend], renders: Renders, size: Vec2) =
  renderFrame(renderer.window.handle, renders, size.x, size.y)

proc endFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  discard renderer

proc backendName*(renderer: FigRenderer[SiwinRenderBackend]): string =
  siwinBackendName(renderer.window.handle)

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: native dynlib + " & suffix

proc siwinWindowTitle*(
    renderer: FigRenderer[SiwinRenderBackend],
    window: Window,
    suffix = "Siwin RenderList",
): string =
  discard window
  "figdraw: " & renderer.backendName() & " + " & suffix
