## Native Nim dynamic-library facade generated through Binny.

import vmath
import pkg/pixie as pixie

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

proc newPixieImage*(width, height: int): Image {.exportabi.} =
  pixie.newImage(width, height)

proc readPixieImage*(filePath: string): Image {.exportabi.} =
  pixie.readImage(filePath)

proc decodePixieImage*(data: string): Image {.exportabi.} =
  pixie.decodeImage(data)

proc writePixieImage*(image: Image, filePath: string) {.exportabi.} =
  image.writeFile(filePath)

proc copyImage*(image: Image): Image {.exportabi.} =
  image.copy()

proc resizeImage*(image: Image, width, height: int): Image {.exportabi.} =
  image.resize(width, height)

proc cropImage*(image: Image, x, y, width, height: int): Image {.exportabi.} =
  image.subImage(x, y, width, height)

proc imageWidth*(image: Image): int {.exportabi.} =
  image.width

proc imageHeight*(image: Image): int {.exportabi.} =
  image.height

proc imagePixel*(image: Image, x, y: int): ColorRGBA {.exportabi.} =
  image[x, y].rgba()

proc setImagePixel*(image: Image, x, y: int, color: ColorRGBA) {.exportabi.} =
  image[x, y] = color

proc fillImage*(image: Image, color: ColorRGBA) {.exportabi.} =
  image.fill(color)

proc flipImageHorizontal*(image: Image) {.exportabi.} =
  image.flipHorizontal()

proc flipImageVertical*(image: Image) {.exportabi.} =
  image.flipVertical()

proc rotateImage90*(image: Image) {.exportabi.} =
  image.rotate90()

proc applyImageOpacity*(image: Image, opacity: float32) {.exportabi.} =
  image.applyOpacity(opacity)

proc invertImage*(image: Image) {.exportabi.} =
  image.invert()

proc imageIsTransparent*(image: Image): bool {.exportabi.} =
  image.isTransparent()

proc imageIsOpaque*(image: Image): bool {.exportabi.} =
  image.isOpaque()

proc figImageId*(name: string): ImageId {.exportabi.} =
  imgId(name)

proc loadFigImage*(filePath: string): ImageId {.exportabi.} =
  loadImage(filePath)

proc putFigImage*(id: ImageId, image: Image) {.exportabi.} =
  loadImage(id, image)

proc clearFigImage*(id: ImageId) {.exportabi.} =
  clearImage(id)

proc hasFigImage*(id: ImageId): bool {.exportabi.} =
  hasImage(id)

proc newFigSiwinApp*(
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

proc siwinFirstStep*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.firstStep()

proc siwinStep*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.step()

proc siwinRedraw*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.redraw()

proc siwinClose*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.close()

proc siwinOpened*(appHandle: NativeSiwinApp): bool {.exportabi.} =
  siwinApp(appHandle).window.opened

proc siwinWindowSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
  let size = siwinApp(appHandle).window.size
  NativeWindowSize(w: size.x, h: size.y)

proc siwinRefreshUiScale*(appHandle: NativeSiwinApp) {.exportabi.} =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)

proc siwinBackendName*(appHandle: NativeSiwinApp): string {.exportabi.} =
  siwinApp(appHandle).renderer.siwinBackendName()

proc siwinDisplayServerName*(appHandle: NativeSiwinApp): string {.exportabi.} =
  siwinApp(appHandle).window.siwinDisplayServerName()

proc renderSiwinFrame*(
    appHandle: NativeSiwinApp, renders: Renders, width, height: float32
) {.exportabi.} =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  var nodes = renders
  app.renderer.renderFrame(nodes, vec2(width, height))
  app.renderer.endFrame()

proc renderSiwinFrame*(appHandle: NativeSiwinApp, renders: Renders) {.exportabi.} =
  let size = siwinApp(appHandle).window.backingSize()
  renderSiwinFrame(appHandle, renders, size.x.float32, size.y.float32)
