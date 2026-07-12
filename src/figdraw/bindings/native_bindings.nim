when defined(useNativeDynlib):
  ## Source-compatible FigDraw/Siwin facade backed by the native Nim dynamic library.

  import figdraw_native_abi

  export figdraw_native_abi

  const
    UseVulkanBackend* = false
    UseMetalBackend* = false

  type
    ZLevel* = int8
    Color* = Fill
    ImageRef* = ImageId

    FontStyle* = object
      font*: FigFont
      color*: Fill

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

  proc color*(value: ColorRGBA): Fill =
    fill(value)

  converter toFill*(value: ColorRGBA): Fill =
    fill(value)

  let clearColor* = fill(rgba(0, 0, 0, 0))

  proc fs*(font: FigFont, color: Fill = fill(rgba(0, 0, 0, 255))): FontStyle =
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
      raise newException(
        ValueError, "native dynlib typeset does not support multiple spans"
      )
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

  proc renderFrame*(
      renderer: FigRenderer[SiwinRenderBackend], renders: var Renders, size: Vec2
  ) =
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

else:
  ## Native Nim dynamic-library facade generated through Binny.

  import std/options
  import vmath
  import pkg/pixie as pixie
  import siwin/[clipboards, colorutils]

  import figdraw/commons
  import figdraw/fignodes
  import figdraw/figrender
  import figdraw/windowing/siwinshim

  type
    NativeWindowSize* = object
      w*, h*: int32

    NativeWindowPos* = object
      x*, y*: int32

    NativePoint* = object
      x*, y*: float32

    NativePopupPlacement* = object
      anchorX*, anchorY*: int32
      anchorWidth*, anchorHeight*: int32
      width*, height*: int32
      anchor*, gravity*: Edge
      offsetX*, offsetY*: int32
      constraintAdjustment*: set[PopupConstraintAdjustment]
      reactive*: bool

    NativeSiwinApp* = object
      raw*: pointer

    SiwinApp = ref object
      window: Window
      renderer: FigRenderer[SiwinRenderBackend]
      autoScale: bool
      title: string

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

  func siwinPlacement(value: NativePopupPlacement): PopupPlacement =
    PopupPlacement(
      anchorRectPos: ivec2(value.anchorX, value.anchorY),
      anchorRectSize: ivec2(value.anchorWidth, value.anchorHeight),
      size: ivec2(value.width, value.height),
      anchor: value.anchor,
      gravity: value.gravity,
      offset: ivec2(value.offsetX, value.offsetY),
      constraintAdjustment: value.constraintAdjustment,
      reactive: value.reactive,
    )

  func nativePlacement(value: PopupPlacement): NativePopupPlacement =
    NativePopupPlacement(
      anchorX: value.anchorRectPos.x,
      anchorY: value.anchorRectPos.y,
      anchorWidth: value.anchorRectSize.x,
      anchorHeight: value.anchorRectSize.y,
      width: value.size.x,
      height: value.size.y,
      anchor: value.anchor,
      gravity: value.gravity,
      offsetX: value.offset.x,
      offsetY: value.offset.y,
      constraintAdjustment: value.constraintAdjustment,
      reactive: value.reactive,
    )

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

  proc typeset*(
      box: Rect,
      font: FigFont,
      color: Fill,
      text: string,
      hAlign = FontHorizontal.Left,
      vAlign = FontVertical.Top,
      minContent = false,
      wrap = true,
  ): GlyphArrangement {.exportabi.} =
    typeset(box, [(fs(font, color), text)], hAlign, vAlign, minContent, wrap)

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
      SiwinApp(
        window: window,
        renderer: renderer,
        autoScale: window.configureUiScale(),
        title: title,
      )
    )

  proc newFigSiwinPopup*(
      parentHandle: NativeSiwinApp,
      placement: NativePopupPlacement,
      atlasSize: int,
      pixelScale: float32,
      transparent, grab: bool,
  ): NativeSiwinApp {.exportabi.} =
    let window = newPopupWindow(
      sharedSiwinGlobals(),
      siwinApp(parentHandle).window,
      placement.siwinPlacement(),
      transparent,
      grab,
    )
    let renderer =
      when UseVulkanBackend:
        newFigRenderer(atlasSize, SiwinRenderBackend(), pixelScale)
      else:
        newFigRenderer(atlasSize, SiwinRenderBackend(window: window), pixelScale)
    renderer.setupBackend(window)
    wrap(
      SiwinApp(window: window, renderer: renderer, autoScale: window.configureUiScale())
    )

  proc firstStep*(appHandle: NativeSiwinApp, makeVisible: bool) {.exportabi.} =
    siwinApp(appHandle).window.firstStep(makeVisible)

  proc firstStep*(appHandle: NativeSiwinApp) {.exportabi.} =
    firstStep(appHandle, true)

  proc step*(appHandle: NativeSiwinApp) {.exportabi.} =
    siwinApp(appHandle).window.step()

  proc redraw*(appHandle: NativeSiwinApp) {.exportabi.} =
    siwinApp(appHandle).window.redraw()

  proc close*(appHandle: NativeSiwinApp) {.exportabi.} =
    siwinApp(appHandle).window.close()

  proc opened*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.opened

  proc siwinWindowSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
    let size = siwinApp(appHandle).window.size
    NativeWindowSize(w: size.x, h: size.y)

  proc siwinSetWindowSize*(
      appHandle: NativeSiwinApp, width, height: int32
  ) {.exportabi.} =
    siwinApp(appHandle).window.size = ivec2(width, height)

  proc siwinWindowPos*(appHandle: NativeSiwinApp): NativeWindowPos {.exportabi.} =
    let pos = siwinApp(appHandle).window.pos
    NativeWindowPos(x: pos.x, y: pos.y)

  proc siwinSetWindowPos*(appHandle: NativeSiwinApp, x, y: int32) {.exportabi.} =
    siwinApp(appHandle).window.pos = ivec2(x, y)

  proc siwinSetTitle*(appHandle: NativeSiwinApp, title: string) {.exportabi.} =
    let app = siwinApp(appHandle)
    app.window.title = title
    app.title = title

  proc siwinTitle*(appHandle: NativeSiwinApp): string {.exportabi.} =
    siwinApp(appHandle).title

  proc siwinIsVisible*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.visible

  proc siwinSetVisible*(appHandle: NativeSiwinApp, visible: bool) {.exportabi.} =
    siwinApp(appHandle).window.visible = visible

  proc siwinIsFocused*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.focused

  proc siwinIsFullscreen*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.fullscreen

  proc siwinSetFullscreen*(appHandle: NativeSiwinApp, fullscreen: bool) {.exportabi.} =
    siwinApp(appHandle).window.fullscreen = fullscreen

  proc siwinIsMaximized*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.maximized

  proc siwinSetMaximized*(appHandle: NativeSiwinApp, maximized: bool) {.exportabi.} =
    siwinApp(appHandle).window.maximized = maximized

  proc siwinIsMinimized*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.minimized

  proc siwinSetMinimized*(appHandle: NativeSiwinApp, minimized: bool) {.exportabi.} =
    siwinApp(appHandle).window.minimized = minimized

  proc siwinIsResizable*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.resizable

  proc siwinSetResizable*(appHandle: NativeSiwinApp, resizable: bool) {.exportabi.} =
    siwinApp(appHandle).window.resizable = resizable

  proc siwinIsFrameless*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.frameless

  proc siwinIsTransparent*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.transparent

  proc siwinSetFrameless*(appHandle: NativeSiwinApp, frameless: bool) {.exportabi.} =
    siwinApp(appHandle).window.frameless = frameless

  proc siwinMinSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
    let size = siwinApp(appHandle).window.minSize
    NativeWindowSize(w: size.x, h: size.y)

  proc siwinSetMinSize*(appHandle: NativeSiwinApp, width, height: int32) {.exportabi.} =
    siwinApp(appHandle).window.minSize = ivec2(width, height)

  proc siwinMaxSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
    let size = siwinApp(appHandle).window.maxSize
    NativeWindowSize(w: size.x, h: size.y)

  proc siwinSetMaxSize*(appHandle: NativeSiwinApp, width, height: int32) {.exportabi.} =
    siwinApp(appHandle).window.maxSize = ivec2(width, height)

  proc siwinUsesCustomTitlebar*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.customTitlebar

  proc siwinSupportsCustomTitlebar*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.supportsCustomTitlebar()

  proc siwinSetCustomTitlebar*(appHandle: NativeSiwinApp, enabled: bool) {.exportabi.} =
    siwinApp(appHandle).window.customTitlebar = enabled

  proc siwinSetTitleRegion*(
      appHandle: NativeSiwinApp, x, y, width, height: float32
  ) {.exportabi.} =
    siwinApp(appHandle).window.setTitleRegion(vec2(x, y), vec2(width, height))

  proc siwinSetInputRegion*(
      appHandle: NativeSiwinApp, x, y, width, height: float32
  ) {.exportabi.} =
    siwinApp(appHandle).window.setInputRegion(vec2(x, y), vec2(width, height))

  proc siwinSetBorderWidth*(
      appHandle: NativeSiwinApp, innerWidth, outerWidth, diagonalSize: float32
  ) {.exportabi.} =
    siwinApp(appHandle).window.setBorderWidth(innerWidth, outerWidth, diagonalSize)

  proc siwinStartInteractiveMove*(
      appHandle: NativeSiwinApp, x, y: float32
  ) {.exportabi.} =
    siwinApp(appHandle).window.startInteractiveMove(some(vec2(x, y)))

  proc siwinStartInteractiveResize*(
      appHandle: NativeSiwinApp, edge: Edge, x, y: float32
  ) {.exportabi.} =
    siwinApp(appHandle).window.startInteractiveResize(edge, some(vec2(x, y)))

  proc siwinShowWindowMenu*(appHandle: NativeSiwinApp, x, y: float32) {.exportabi.} =
    siwinApp(appHandle).window.showWindowMenu(some(vec2(x, y)))

  proc siwinSetBuiltinCursor*(
      appHandle: NativeSiwinApp, cursor: BuiltinCursor
  ) {.exportabi.} =
    siwinApp(appHandle).window.cursor = Cursor(kind: builtin, builtin: cursor)

  proc siwinMousePos*(appHandle: NativeSiwinApp): NativePoint {.exportabi.} =
    let pos = siwinApp(appHandle).window.mouse.pos
    NativePoint(x: pos.x, y: pos.y)

  proc siwinMouseButtonPressed*(
      appHandle: NativeSiwinApp, button: MouseButton
  ): bool {.exportabi.} =
    button in siwinApp(appHandle).window.mouse.pressed

  proc siwinKeyPressed*(appHandle: NativeSiwinApp, key: Key): bool {.exportabi.} =
    key in siwinApp(appHandle).window.keyboard.pressed

  proc siwinModifierPressed*(
      appHandle: NativeSiwinApp, modifier: ModifierKey
  ): bool {.exportabi.} =
    modifier in siwinApp(appHandle).window.keyboard.modifiers

  proc siwinSetVsync*(appHandle: NativeSiwinApp, enabled: bool) {.exportabi.} =
    siwinApp(appHandle).window.vsync = enabled

  proc siwinUsesSeparateTouch*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.separateTouch

  proc siwinSetSeparateTouch*(appHandle: NativeSiwinApp, enabled: bool) {.exportabi.} =
    siwinApp(appHandle).window.separateTouch = enabled

  proc siwinCanBecomeKeyWindow*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.canBecomeKeyWindow()

  proc siwinSetCanBecomeKeyWindow*(
      appHandle: NativeSiwinApp, enabled: bool
  ) {.exportabi.} =
    siwinApp(appHandle).window.canBecomeKeyWindow = enabled

  proc siwinCanBecomeMainWindow*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.canBecomeMainWindow()

  proc siwinSetCanBecomeMainWindow*(
      appHandle: NativeSiwinApp, enabled: bool
  ) {.exportabi.} =
    siwinApp(appHandle).window.canBecomeMainWindow = enabled

  proc siwinSetIcon*(appHandle: NativeSiwinApp, image: Image) {.exportabi.} =
    if image.isNil or image.data.len == 0:
      siwinApp(appHandle).window.icon = nil
    else:
      siwinApp(appHandle).window.icon = PixelBuffer(
        data: image.data[0].addr,
        size: ivec2(image.width.int32, image.height.int32),
        format: rgbx_32bit,
      )

  proc siwinClearIcon*(appHandle: NativeSiwinApp) {.exportabi.} =
    siwinApp(appHandle).window.icon = nil

  proc siwinClipboardText*(appHandle: NativeSiwinApp): string {.exportabi.} =
    siwinApp(appHandle).window.clipboard.text

  proc siwinSetClipboardText*(appHandle: NativeSiwinApp, value: string) {.exportabi.} =
    siwinApp(appHandle).window.clipboard.text = value

  proc siwinClipboardFiles*(appHandle: NativeSiwinApp): seq[string] {.exportabi.} =
    siwinApp(appHandle).window.clipboard.files

  proc siwinSetClipboardFiles*(
      appHandle: NativeSiwinApp, value: seq[string]
  ) {.exportabi.} =
    siwinApp(appHandle).window.clipboard.files = value

  proc siwinClipboardData*(
      appHandle: NativeSiwinApp, mimeType: string
  ): string {.exportabi.} =
    siwinApp(appHandle).window.clipboard[mimeType]

  proc siwinSetClipboardData*(
      appHandle: NativeSiwinApp, mimeType, value: string
  ) {.exportabi.} =
    siwinApp(appHandle).window.clipboard[mimeType] = value

  proc siwinUiScale*(appHandle: NativeSiwinApp): float32 {.exportabi.} =
    siwinApp(appHandle).window.uiScale()

  proc siwinIsPopup*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.isPopup

  proc siwinPopupGrab*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.popupGrab

  proc siwinPopupOpen*(appHandle: NativeSiwinApp): bool {.exportabi.} =
    siwinApp(appHandle).window.popupOpen

  proc siwinPopupPlacement*(
      appHandle: NativeSiwinApp
  ): NativePopupPlacement {.exportabi.} =
    siwinApp(appHandle).window.placement().nativePlacement()

  proc siwinRepositionPopup*(
      appHandle: NativeSiwinApp, placement: NativePopupPlacement
  ) {.exportabi.} =
    siwinApp(appHandle).window.reposition(placement.siwinPlacement())

  proc siwinRefreshUiScale*(appHandle: NativeSiwinApp) {.exportabi.} =
    let app = siwinApp(appHandle)
    app.window.refreshUiScale(app.autoScale)

  proc siwinBackendName*(appHandle: NativeSiwinApp): string {.exportabi.} =
    siwinApp(appHandle).renderer.siwinBackendName()

  proc siwinDisplayServerName*(appHandle: NativeSiwinApp): string {.exportabi.} =
    siwinApp(appHandle).window.siwinDisplayServerName()

  proc renderFrame*(
      appHandle: NativeSiwinApp, renders: Renders, width, height: float32
  ) {.exportabi.} =
    let app = siwinApp(appHandle)
    app.window.refreshUiScale(app.autoScale)
    app.renderer.beginFrame()
    var nodes = renders
    app.renderer.renderFrame(nodes, vec2(width, height))
    app.renderer.endFrame()

  proc renderFrame*(appHandle: NativeSiwinApp, renders: Renders) {.exportabi.} =
    let size = siwinApp(appHandle).window.backingSize()
    renderFrame(appHandle, renders, size.x.float32, size.y.float32)
