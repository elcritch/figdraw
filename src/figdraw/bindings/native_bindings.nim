## Native Nim dynamic-library facade generated through Binny.

import std/[options, unicode]
import vmath
import pkg/pixie as pixie
import pkg/pixie/fileformats/png as png
import siwin/[clipboards, colorutils]

import figdraw/commons
import figdraw/common/fonttypes as fonttypes
import figdraw/fignodes
import figdraw/figrender
import figdraw/windowing/siwinshim

type
  NativeCloseCallback = proc(context: pointer) {.cdecl.}
  NativeResizeCallback =
    proc(context: pointer, width, height: int32, initial: bool) {.cdecl.}
  NativeRenderCallback = proc(context: pointer) {.cdecl.}
  NativeWindowMoveCallback = proc(context: pointer, x, y: int32) {.cdecl.}
  NativeMouseMoveCallback = proc(context: pointer, x, y: float32, kind: uint8) {.cdecl.}
  NativeMouseButtonCallback =
    proc(context: pointer, button: MouseButton, pressed, generated: bool) {.cdecl.}
  NativeScrollCallback =
    proc(context: pointer, delta, deltaX: float, device: uint8) {.cdecl.}
  NativeKeyCallback = proc(
    context: pointer, key: Key, pressed, repeated, generated: bool, modifierMask: uint8
  ) {.cdecl.}
  NativeTextInputCallback =
    proc(context, text: pointer, textLen: int, repeated: bool) {.cdecl.}
  NativeStateBoolChangedCallback =
    proc(context: pointer, value: bool, kind: uint8, isExternal: bool) {.cdecl.}
  NativePopupCallback = proc(context: pointer, reason: uint8) {.cdecl.}

  PopupConstraintAdjustments* = set[PopupConstraintAdjustment]
  WindowVisualCapabilities* = set[WindowVisualCapability]
  FigFlagSet* = set[FigFlags]
  IntSlice* = Slice[int]

  NativeWindowSize* = object
    w*, h*: int32

  NativeLogicalSize* = object
    w*, h*: float32

  NativeWindowPos* = object
    x*, y*: int32

  NativePoint* = object
    x*, y*: float32

  NativeWindowVisualRegion* = object
    x*, y*, width*, height*: int32

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

  SiwinApp = ref object
    window: Window
    renderer: FigRenderer[SiwinRenderBackend]
    autoScale: bool
    title: string

proc utf8RunesFromRunes*(runes: seq[Rune]): fonttypes.Utf8Runes =
  ## Creates UTF-8-backed storage from a compatibility rune sequence.
  fonttypes.initUtf8Runes(runes)

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

proc newPixieImage*(width, height: int): pixie.Image =
  pixie.newImage(width, height)

proc readPixieImage*(filePath: string): pixie.Image =
  pixie.readImage(filePath)

proc decodePixieImage*(data: string): pixie.Image =
  pixie.decodeImage(data)

proc encodePng*(value: pixie.Image): string =
  png.encodePng(value)

proc writePixieImage*(value: pixie.Image, filePath: string) =
  value.writeFile(filePath)

proc copyImage*(value: pixie.Image): pixie.Image =
  value.copy()

proc imageWidth*(value: pixie.Image): int =
  value.width

proc imageHeight*(value: pixie.Image): int =
  value.height

proc imagePixel*(value: pixie.Image, x, y: int): ColorRGBA =
  value[x, y].rgba()

proc setImagePixel*(value: pixie.Image, x, y: int, color: ColorRGBA) =
  value[x, y] = color

proc fillImage*(value: pixie.Image, color: ColorRGBA) =
  value.fill(color)

proc putFigImage*(id: ImageId, value: pixie.Image) =
  loadImage(id, value)

proc replaceFigImage*(id: ImageId, value: pixie.Image) =
  replaceImage(id, value)

proc newFigSiwinApp*(
    width, height: int32,
    title: string,
    atlasSize: int,
    pixelScale: float32,
    fullscreen, vsync: bool,
    msaa: int32,
    resizable, frameless, transparent: bool,
): NativeSiwinApp =
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
): NativeSiwinApp =
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

func nativeModifierMask(modifiers: set[ModifierKey]): uint8 =
  for modifier in modifiers:
    result = result or (1'u8 shl modifier.ord)

proc siwinSetEventCallbacks*(
    appHandle: NativeSiwinApp,
    context, closeCallback, resizeCallback, renderCallback, windowMoveCallback,
      mouseMoveCallback, mouseButtonCallback, scrollCallback, keyCallback,
      textInputCallback, stateBoolChangedCallback, popupCallback: pointer,
) =
  let app = siwinApp(appHandle)
  if closeCallback == nil:
    app.window.eventsHandler.onClose = nil
  else:
    app.window.eventsHandler.onClose = proc(e: CloseEvent) =
      discard e
      cast[NativeCloseCallback](closeCallback)(context)
  if resizeCallback == nil:
    app.window.eventsHandler.onResize = nil
  else:
    app.window.eventsHandler.onResize = proc(e: ResizeEvent) =
      cast[NativeResizeCallback](resizeCallback)(context, e.size.x, e.size.y, e.initial)
  if renderCallback == nil:
    app.window.eventsHandler.onRender = nil
  else:
    app.window.eventsHandler.onRender = proc(e: RenderEvent) =
      discard e
      cast[NativeRenderCallback](renderCallback)(context)
  if windowMoveCallback == nil:
    app.window.eventsHandler.onWindowMove = nil
  else:
    app.window.eventsHandler.onWindowMove = proc(e: WindowMoveEvent) =
      cast[NativeWindowMoveCallback](windowMoveCallback)(context, e.pos.x, e.pos.y)
  if mouseMoveCallback == nil:
    app.window.eventsHandler.onMouseMove = nil
  else:
    app.window.eventsHandler.onMouseMove = proc(e: MouseMoveEvent) =
      cast[NativeMouseMoveCallback](mouseMoveCallback)(
        context, e.pos.x, e.pos.y, e.kind.ord.uint8
      )
  if mouseButtonCallback == nil:
    app.window.eventsHandler.onMouseButton = nil
  else:
    app.window.eventsHandler.onMouseButton = proc(e: MouseButtonEvent) =
      cast[NativeMouseButtonCallback](mouseButtonCallback)(
        context, e.button, e.pressed, e.generated
      )
  if scrollCallback == nil:
    app.window.eventsHandler.onScroll = nil
  else:
    app.window.eventsHandler.onScroll = proc(e: ScrollEvent) =
      cast[NativeScrollCallback](scrollCallback)(
        context, e.delta, e.deltaX, e.device.ord.uint8
      )
  if keyCallback == nil:
    app.window.eventsHandler.onKey = nil
  else:
    app.window.eventsHandler.onKey = proc(e: KeyEvent) =
      cast[NativeKeyCallback](keyCallback)(
        context,
        e.key,
        e.pressed,
        e.repeated,
        e.generated,
        e.modifiers.nativeModifierMask(),
      )
  if textInputCallback == nil:
    app.window.eventsHandler.onTextInput = nil
  else:
    app.window.eventsHandler.onTextInput = proc(e: TextInputEvent) =
      let text =
        if e.text.len > 0:
          unsafeAddr e.text[0]
        else:
          nil
      cast[NativeTextInputCallback](textInputCallback)(
        context, text, e.text.len, e.repeated
      )
  if stateBoolChangedCallback == nil:
    app.window.eventsHandler.onStateBoolChanged = nil
  else:
    app.window.eventsHandler.onStateBoolChanged = proc(e: StateBoolChangedEvent) =
      cast[NativeStateBoolChangedCallback](stateBoolChangedCallback)(
        context, e.value, e.kind.ord.uint8, e.isExternal
      )
  if popupCallback == nil:
    app.window.eventsHandler.onPopupDone = nil
  else:
    app.window.eventsHandler.onPopupDone = proc(e: PopupEvent) =
      cast[NativePopupCallback](popupCallback)(context, e.reason.ord.uint8)

proc siwinWindowSize*(appHandle: NativeSiwinApp): NativeWindowSize =
  let size = siwinApp(appHandle).window.size
  NativeWindowSize(w: size.x, h: size.y)

proc siwinBackingSize*(appHandle: NativeSiwinApp): NativeWindowSize =
  let size = siwinApp(appHandle).window.backingSize()
  NativeWindowSize(w: size.x, h: size.y)

proc siwinLogicalSize*(appHandle: NativeSiwinApp): NativeLogicalSize =
  let size = siwinApp(appHandle).window.logicalSize()
  NativeLogicalSize(w: size.x, h: size.y)

proc siwinSetWindowSize*(appHandle: NativeSiwinApp, width, height: int32) =
  siwinApp(appHandle).window.size = ivec2(width, height)

proc siwinWindowPos*(appHandle: NativeSiwinApp): NativeWindowPos =
  let pos = siwinApp(appHandle).window.pos
  NativeWindowPos(x: pos.x, y: pos.y)

proc siwinSetWindowPos*(appHandle: NativeSiwinApp, x, y: int32) =
  siwinApp(appHandle).window.pos = ivec2(x, y)

proc siwinSetTitle*(appHandle: NativeSiwinApp, title: string) =
  let app = siwinApp(appHandle)
  app.window.title = title
  app.title = title

proc siwinTitle*(appHandle: NativeSiwinApp): string =
  siwinApp(appHandle).title

proc siwinNativeWindowKey*(appHandle: NativeSiwinApp): pointer =
  cast[pointer](siwinApp(appHandle).window)

proc siwinWindowHandle*(appHandle: NativeSiwinApp): Window =
  siwinApp(appHandle).window

proc siwinMinSize*(appHandle: NativeSiwinApp): NativeWindowSize =
  let size = siwinApp(appHandle).window.minSize
  NativeWindowSize(w: size.x, h: size.y)

proc siwinSetMinSize*(appHandle: NativeSiwinApp, width, height: int32) =
  siwinApp(appHandle).window.minSize = ivec2(width, height)

proc siwinMaxSize*(appHandle: NativeSiwinApp): NativeWindowSize =
  let size = siwinApp(appHandle).window.maxSize
  NativeWindowSize(w: size.x, h: size.y)

proc siwinSetMaxSize*(appHandle: NativeSiwinApp, width, height: int32) =
  siwinApp(appHandle).window.maxSize = ivec2(width, height)

proc siwinSetTitleRegion*(appHandle: NativeSiwinApp, x, y, width, height: float32) =
  siwinApp(appHandle).window.setTitleRegion(vec2(x, y), vec2(width, height))

proc siwinSetInputRegion*(appHandle: NativeSiwinApp, x, y, width, height: float32) =
  siwinApp(appHandle).window.setInputRegion(vec2(x, y), vec2(width, height))

proc siwinStartInteractiveMove*(appHandle: NativeSiwinApp, x, y: float32) =
  siwinApp(appHandle).window.startInteractiveMove(some(vec2(x, y)))

proc siwinStartInteractiveResize*(
    appHandle: NativeSiwinApp, edge: Edge, x, y: float32
) =
  siwinApp(appHandle).window.startInteractiveResize(edge, some(vec2(x, y)))

proc siwinShowWindowMenu*(appHandle: NativeSiwinApp, x, y: float32) =
  siwinApp(appHandle).window.showWindowMenu(some(vec2(x, y)))

proc siwinSetBuiltinCursor*(appHandle: NativeSiwinApp, cursor: BuiltinCursor) =
  siwinApp(appHandle).window.cursor = Cursor(kind: builtin, builtin: cursor)

proc siwinMousePos*(appHandle: NativeSiwinApp): NativePoint =
  let pos = siwinApp(appHandle).window.mouse.pos
  NativePoint(x: pos.x, y: pos.y)

proc siwinSetIcon*(appHandle: NativeSiwinApp, value: pixie.Image) =
  let image = value
  if image.isNil or image.data.len == 0:
    siwinApp(appHandle).window.icon = nil
  else:
    siwinApp(appHandle).window.icon = PixelBuffer(
      data: image.data[0].addr,
      size: ivec2(image.width.int32, image.height.int32),
      format: rgbx_32bit,
    )

proc siwinPopupPlacement*(appHandle: NativeSiwinApp): NativePopupPlacement =
  siwinApp(appHandle).window.placement().nativePlacement()

proc siwinRepositionPopup*(appHandle: NativeSiwinApp, placement: NativePopupPlacement) =
  siwinApp(appHandle).window.reposition(placement.siwinPlacement())

proc siwinRefreshUiScale*(appHandle: NativeSiwinApp) =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)

proc siwinTrySetBackdrop*(
    appHandle: NativeSiwinApp,
    kind: WindowBackdropKind,
    material: WindowBackdropMaterial,
    regions: openArray[NativeWindowVisualRegion],
): bool =
  var nativeRegions = newSeqOfCap[WindowVisualRegion](regions.len)
  for region in regions:
    nativeRegions.add WindowVisualRegion(
      pos: ivec2(region.x, region.y), size: ivec2(region.width, region.height)
    )
  let config =
    case kind
    of wbkNone, wbkBlur:
      WindowBackdropConfig(kind: kind, regions: nativeRegions)
    of wbkMaterial:
      WindowBackdropConfig(kind: kind, material: material, regions: nativeRegions)
  siwinApp(appHandle).window.trySetBackdrop(config)

proc siwinBackendName*(appHandle: NativeSiwinApp): string =
  siwinApp(appHandle).renderer.siwinBackendName()

proc siwinBackendKind*(appHandle: NativeSiwinApp): RendererBackendKind =
  siwinApp(appHandle).renderer.backendKind()

proc setTextLcdFiltering*(appHandle: NativeSiwinApp, enabled: bool) =
  siwinApp(appHandle).renderer.setTextLcdFiltering(enabled)

proc textLcdFiltering*(appHandle: NativeSiwinApp): bool =
  siwinApp(appHandle).renderer.textLcdFiltering()

proc setTextSubpixelPositioning*(appHandle: NativeSiwinApp, enabled: bool) =
  siwinApp(appHandle).renderer.setTextSubpixelPositioning(enabled)

proc textSubpixelPositioning*(appHandle: NativeSiwinApp): bool =
  siwinApp(appHandle).renderer.textSubpixelPositioning()

proc setTextSubpixelGlyphVariants*(appHandle: NativeSiwinApp, enabled: bool) =
  siwinApp(appHandle).renderer.setTextSubpixelGlyphVariants(enabled)

proc textSubpixelGlyphVariants*(appHandle: NativeSiwinApp): bool =
  siwinApp(appHandle).renderer.textSubpixelGlyphVariants()

proc renderFrame*(
    appHandle: NativeSiwinApp,
    renders: var Renders,
    width, height: float32,
    clearMain: bool,
    clearR, clearG, clearB, clearA: float32,
) =
  let app = siwinApp(appHandle)
  app.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  app.renderer.renderFrame(
    renders,
    vec2(width, height),
    clearMain = clearMain,
    clearColor = color(clearR, clearG, clearB, clearA),
  )
  app.renderer.endFrame()
