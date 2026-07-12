## Native Nim dynamic-library facade generated through Binny.

import std/[options, unicode]
import vmath
import pkg/pixie as pixie
import pkg/pixie/fileformats/png as png
import siwin/[clipboards, colorutils]

import figdraw/commons
import figdraw/common/fontutils as fontutils
import figdraw/fignodes
import figdraw/figrender
import figdraw/utils/drawutils
import figdraw/windowing/siwinshim

type
  NativeResizeCallback =
    proc(context: pointer, width, height: int32, initial: bool) {.cdecl.}
  NativeRenderCallback = proc(context: pointer) {.cdecl.}

  PopupConstraintAdjustments* = set[PopupConstraintAdjustment]
  FigFlagSet* = set[FigFlags]
  Vec2s* = seq[Vec2]
  Figs* = seq[Fig]
  FigIdxs* = seq[FigIdx]
  TypefaceIds* = seq[TypefaceId]
  FontFeatures* = seq[FontFeature]
  FontVariations* = seq[FontVariation]
  Strings* = seq[string]
  ColorRGBXs* = seq[ColorRGBX]
  GlyphFonts* = seq[GlyphFont]
  Fills* = seq[Fill]
  Runes* = seq[Rune]
  DrawableOps* = seq[DrawableOp]
  ArrangedGlyphs* = seq[ArrangedGlyph]
  Rects* = seq[Rect]
  IntSlice* = Slice[int]
  IntSlices* = seq[IntSlice]
  TextCaretPositions* = seq[TextCaretPosition]

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
    constraintAdjustment*: PopupConstraintAdjustments
    reactive*: bool

  NativeSiwinApp* = object
    raw*: pointer

  NativeImage* = object
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
defineHandleHooks(NativeImage, Image)

proc wrap(value: SiwinApp): NativeSiwinApp =
  retainRaw[SiwinApp](cast[pointer](value))
  result.raw = cast[pointer](value)

template siwinApp(value: NativeSiwinApp): SiwinApp =
  cast[SiwinApp](value.raw)

proc wrap(value: Image): NativeImage =
  retainRaw[Image](cast[pointer](value))
  result.raw = cast[pointer](value)

template image(value: NativeImage): Image =
  cast[Image](value.raw)

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

proc isNil*(value: NativeImage): bool {.exportabi.} =
  value.raw == nil

proc newPixieImage*(width, height: int): NativeImage {.exportabi.} =
  wrap(pixie.newImage(width, height))

proc readPixieImage*(filePath: string): NativeImage {.exportabi.} =
  wrap(pixie.readImage(filePath))

proc decodePixieImage*(data: string): NativeImage {.exportabi.} =
  wrap(pixie.decodeImage(data))

proc encodePng*(value: NativeImage): string {.exportabi.} =
  png.encodePng(value.image)

proc writePixieImage*(value: NativeImage, filePath: string) {.exportabi.} =
  value.image.writeFile(filePath)

proc copyImage*(value: NativeImage): NativeImage {.exportabi.} =
  wrap(value.image.copy())

proc resizeImage*(value: NativeImage, width, height: int): NativeImage {.exportabi.} =
  wrap(value.image.resize(width, height))

proc cropImage*(
    value: NativeImage, x, y, width, height: int
): NativeImage {.exportabi.} =
  wrap(value.image.subImage(x, y, width, height))

proc imageWidth*(value: NativeImage): int {.exportabi.} =
  value.image.width

proc imageHeight*(value: NativeImage): int {.exportabi.} =
  value.image.height

proc imagePixel*(value: NativeImage, x, y: int): ColorRGBA {.exportabi.} =
  value.image[x, y].rgba()

proc setImagePixel*(value: NativeImage, x, y: int, color: ColorRGBA) {.exportabi.} =
  value.image[x, y] = color

proc fillImage*(value: NativeImage, color: ColorRGBA) {.exportabi.} =
  value.image.fill(color)

proc flipImageHorizontal*(value: NativeImage) {.exportabi.} =
  value.image.flipHorizontal()

proc flipImageVertical*(value: NativeImage) {.exportabi.} =
  value.image.flipVertical()

proc rotateImage90*(value: NativeImage) {.exportabi.} =
  value.image.rotate90()

proc applyImageOpacity*(value: NativeImage, opacity: float32) {.exportabi.} =
  value.image.applyOpacity(opacity)

proc invertImage*(value: NativeImage) {.exportabi.} =
  value.image.invert()

proc imageIsTransparent*(value: NativeImage): bool {.exportabi.} =
  value.image.isTransparent()

proc imageIsOpaque*(value: NativeImage): bool {.exportabi.} =
  value.image.isOpaque()

proc figImageId*(name: string): ImageId {.exportabi.} =
  imgId(name)

proc loadFigImage*(filePath: string): ImageId {.exportabi.} =
  loadImage(filePath)

proc putFigImage*(id: ImageId, value: NativeImage) {.exportabi.} =
  loadImage(id, value.image)

proc clearFigImage*(id: ImageId) {.exportabi.} =
  clearImage(id)

proc hasFigImage*(id: ImageId): bool {.exportabi.} =
  hasImage(id)

proc typeset*(
    box: Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.exportabi.} =
  fontutils.typeset(box, spans, hAlign, vAlign, minContent, wrap)

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

proc siwinSetEventCallbacks*(
    appHandle: NativeSiwinApp, context, resizeCallback, renderCallback: pointer
) {.exportabi.} =
  let app = siwinApp(appHandle)
  if resizeCallback == nil:
    app.window.eventsHandler.onResize = nil
  else:
    app.window.eventsHandler.onResize = proc(e: ResizeEvent) =
      cast[NativeResizeCallback](resizeCallback)(context, e.size.x, e.size.y, e.initial)
  if renderCallback == nil:
    app.window.eventsHandler.onRender = nil
  else:
    app.window.eventsHandler.onRender = proc(e: RenderEvent) =
      cast[NativeRenderCallback](renderCallback)(context)

proc step*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.step()

proc redraw*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.redraw()

proc makeCurrent*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.makeCurrent()

proc close*(appHandle: NativeSiwinApp) {.exportabi.} =
  siwinApp(appHandle).window.close()

proc opened*(appHandle: NativeSiwinApp): bool {.exportabi.} =
  siwinApp(appHandle).window.opened

proc siwinWindowSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
  let size = siwinApp(appHandle).window.size
  NativeWindowSize(w: size.x, h: size.y)

proc siwinBackingSize*(appHandle: NativeSiwinApp): NativeWindowSize {.exportabi.} =
  let size = siwinApp(appHandle).window.backingSize()
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

proc siwinSetIcon*(appHandle: NativeSiwinApp, value: NativeImage) {.exportabi.} =
  let image = value.image
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

proc siwinBackendKind*(appHandle: NativeSiwinApp): RendererBackendKind {.exportabi.} =
  siwinApp(appHandle).renderer.backendKind()

proc setTextLcdFiltering*(appHandle: NativeSiwinApp, enabled: bool) {.exportabi.} =
  siwinApp(appHandle).renderer.setTextLcdFiltering(enabled)

proc textLcdFiltering*(appHandle: NativeSiwinApp): bool {.exportabi.} =
  siwinApp(appHandle).renderer.textLcdFiltering()

proc setTextSubpixelPositioning*(
    appHandle: NativeSiwinApp, enabled: bool
) {.exportabi.} =
  siwinApp(appHandle).renderer.setTextSubpixelPositioning(enabled)

proc textSubpixelPositioning*(appHandle: NativeSiwinApp): bool {.exportabi.} =
  siwinApp(appHandle).renderer.textSubpixelPositioning()

proc setTextSubpixelGlyphVariants*(
    appHandle: NativeSiwinApp, enabled: bool
) {.exportabi.} =
  siwinApp(appHandle).renderer.setTextSubpixelGlyphVariants(enabled)

proc textSubpixelGlyphVariants*(appHandle: NativeSiwinApp): bool {.exportabi.} =
  siwinApp(appHandle).renderer.textSubpixelGlyphVariants()

proc siwinDisplayServerName*(appHandle: NativeSiwinApp): string {.exportabi.} =
  siwinApp(appHandle).window.siwinDisplayServerName()

proc renderFrame*(
    appHandle: NativeSiwinApp,
    renders: Renders,
    width, height: float32,
    clearMain: bool,
    clearR, clearG, clearB, clearA: float32,
) {.exportabi.} =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  var nodes = renders
  app.renderer.renderFrame(
    nodes,
    vec2(width, height),
    clearMain = clearMain,
    clearColor = color(clearR, clearG, clearB, clearA),
  )
  app.renderer.endFrame()

proc renderFrame*(
    appHandle: NativeSiwinApp, renders: Renders, width, height: float32
) {.exportabi.} =
  renderFrame(appHandle, renders, width, height, true, 1, 1, 1, 1)

proc renderFrame*(appHandle: NativeSiwinApp, renders: Renders) {.exportabi.} =
  let size = siwinApp(appHandle).window.backingSize()
  renderFrame(appHandle, renders, size.x.float32, size.y.float32)
