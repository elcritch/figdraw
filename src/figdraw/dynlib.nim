## Source-compatible FigDraw/Siwin facade backed by the native Nim dynamic library.

import std/[os, strutils, tables, unicode]
import pkg/bumpy as bumpy
import pkg/chroma as chroma
import pkg/vmath as vmath
import figdraw_native_abi

export tables, bumpy, chroma, vmath
export figdraw_native_abi except
  Rect, ColorRGBA, Vec2, Mat4, Rune, FigSelectionRange, figDashedRoundedRectBorder,
  figDottedRoundedRectBorder, figRoundedRectBorder, placeGlyphs, typeset

const
  UseVulkanBackend* = false
  UseMetalBackend* = false
  ShadowCount* = 4
  DefaultDrawableBezierSteps* = 48'u16
  DefaultDrawableArcSteps* = 48'u16
  figdrawTextBackend* {.strdefine.} = "pixie"

type
  ImageRef* = ImageId

  SiwinRenderBackend* = object

  Mouse* = object
    pos*: vmath.Vec2
    pressed*: set[MouseButton]

  Keyboard* = object
    pressed*: set[Key]
    modifiers*: set[ModifierKey]

  Clipboard* = ref object
    window: Window
    mimeTypes: seq[string]

  Window* = ref object
    handle: NativeSiwinApp
    eventsHandler*: WindowEventsHandler
    clipboard*: Clipboard
    wasOpened: bool
    pollReady: bool
    lastMouse: Mouse
    lastKeyboard: Keyboard
    lastPos: vmath.IVec2
    lastFocused, lastFullscreen, lastMaximized, lastFrameless: bool
    lastPopupOpen: bool
    autoScale: bool
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
    size*: vmath.IVec2
    initial*: bool

  WindowMoveEvent* = object
    window*: Window
    pos*: vmath.IVec2

  MouseMoveKind* = enum
    move
    enter
    leave
    moveWhileDragging

  MouseMoveEvent* = object
    window*: Window
    pos*: vmath.Vec2
    kind*: MouseMoveKind

  MouseButtonEvent* = object
    window*: Window
    button*: MouseButton
    pressed*: bool
    generated*: bool

  ScrollDeviceKind* = enum
    unknown
    discrete
    continuous

  ScrollEvent* = object
    window*: Window
    delta*: float
    deltaX*: float
    device*: ScrollDeviceKind

  KeyEvent* = object
    window*: Window
    key*: Key
    pressed*: bool
    repeated*: bool
    generated*: bool
    modifiers*: set[ModifierKey]

  TextInputEvent* = object
    window*: Window
    text*: string
    repeated*: bool

  StateBoolChangedEventKind* = enum
    focus
    fullscreen
    maximized
    frameless

  StateBoolChangedEvent* = object
    window*: Window
    value*: bool
    kind*: StateBoolChangedEventKind
    isExternal*: bool

  PopupDismissReason* = enum
    pdrClientClosed
    pdrCompositorDismissed
    pdrParentClosed

  PopupEvent* = object
    window*: Window
    reason*: PopupDismissReason

  PopupPlacement* = object
    anchorRectPos*: vmath.IVec2
    anchorRectSize*: vmath.IVec2
    size*: vmath.IVec2
    anchor*: Edge
    gravity*: Edge
    offset*: vmath.IVec2
    constraintAdjustment*: set[PopupConstraintAdjustment]
    reactive*: bool

  WindowEventsHandler* = object
    onClose*: proc(e: CloseEvent)
    onRender*: proc(e: RenderEvent)
    onResize*: proc(e: ResizeEvent)
    onWindowMove*: proc(e: WindowMoveEvent)
    onMouseMove*: proc(e: MouseMoveEvent)
    onMouseButton*: proc(e: MouseButtonEvent)
    onScroll*: proc(e: ScrollEvent)
    onKey*: proc(e: KeyEvent)
    onTextInput*: proc(e: TextInputEvent)
    onStateBoolChanged*: proc(e: StateBoolChangedEvent)
    onPopupDone*: proc(e: PopupEvent)

proc dispatchNativeResize(
    context: pointer, width, height: int32, initial: bool
) {.cdecl.} =
  let window = cast[Window](context)
  if window.eventsHandler.onResize != nil:
    window.eventsHandler.onResize(
      ResizeEvent(window: window, size: vmath.ivec2(width, height), initial: initial)
    )

proc dispatchNativeRender(context: pointer) {.cdecl.} =
  let window = cast[Window](context)
  if window.eventsHandler.onRender != nil:
    window.eventsHandler.onRender(RenderEvent(window: window))

proc dispatchNativeKey(
    context: pointer, key: Key, pressed, repeated, generated: bool, modifierMask: uint8
) {.cdecl.} =
  let window = cast[Window](context)
  if window.eventsHandler.onKey != nil:
    var modifiers: set[ModifierKey]
    for modifier in ModifierKey:
      if (modifierMask and (1'u8 shl modifier.ord)) != 0:
        modifiers.incl modifier
    window.eventsHandler.onKey(
      KeyEvent(
        window: window,
        key: key,
        pressed: pressed,
        repeated: repeated,
        generated: generated,
        modifiers: modifiers,
      )
    )

proc dispatchNativeTextInput(
    context, text: pointer, textLen: int, repeated: bool
) {.cdecl.} =
  let window = cast[Window](context)
  if window.eventsHandler.onTextInput != nil:
    var value = newString(textLen)
    if textLen > 0:
      copyMem(value[0].addr, text, textLen)
    window.eventsHandler.onTextInput(
      TextInputEvent(window: window, text: value, repeated: repeated)
    )

proc installEventCallbacks(window: Window) =
  siwinSetEventCallbacks(
    window.handle,
    cast[pointer](window),
    cast[pointer](dispatchNativeResize),
    cast[pointer](dispatchNativeRender),
    cast[pointer](dispatchNativeKey),
    cast[pointer](dispatchNativeTextInput),
  )

converter toNativeRect*(value: bumpy.Rect): figdraw_native_abi.Rect {.inline.} =
  cast[figdraw_native_abi.Rect](value)

converter toRect*(value: figdraw_native_abi.Rect): bumpy.Rect {.inline.} =
  cast[bumpy.Rect](value)

converter toNativeColor*(
    value: chroma.ColorRGBA
): figdraw_native_abi.ColorRGBA {.inline.} =
  cast[figdraw_native_abi.ColorRGBA](value)

converter toColor*(value: figdraw_native_abi.ColorRGBA): chroma.ColorRGBA {.inline.} =
  cast[chroma.ColorRGBA](value)

converter toNativeVec2*(value: vmath.Vec2): figdraw_native_abi.Vec2 {.inline.} =
  cast[figdraw_native_abi.Vec2](value)

converter toVec2*(value: figdraw_native_abi.Vec2): vmath.Vec2 {.inline.} =
  cast[vmath.Vec2](value)

converter toNativeMat4*(value: vmath.Mat4): figdraw_native_abi.Mat4 {.inline.} =
  cast[figdraw_native_abi.Mat4](value)

converter toMat4*(value: figdraw_native_abi.Mat4): vmath.Mat4 {.inline.} =
  cast[vmath.Mat4](value)

converter toNativeRune*(value: unicode.Rune): figdraw_native_abi.Rune {.inline.} =
  cast[figdraw_native_abi.Rune](value)

converter toRune*(value: figdraw_native_abi.Rune): unicode.Rune {.inline.} =
  cast[unicode.Rune](value)

converter toNativeSelectionRange*(
    value: Slice[int16]
): figdraw_native_abi.FigSelectionRange {.inline.} =
  cast[figdraw_native_abi.FigSelectionRange](value)

converter toSelectionRange*(
    value: figdraw_native_abi.FigSelectionRange
): Slice[int16] {.inline.} =
  cast[Slice[int16]](value)

converter toNativeIntSlice*(value: Slice[int]): figdraw_native_abi.IntSlice {.inline.} =
  cast[figdraw_native_abi.IntSlice](value)

converter toIntSlice*(value: figdraw_native_abi.IntSlice): Slice[int] {.inline.} =
  cast[Slice[int]](value)

converter toFill*(value: chroma.ColorRGBA): Fill {.inline.} =
  fill(value.toNativeColor())

converter toFill*(value: chroma.Color): Fill {.inline.} =
  fill(value.rgba().toNativeColor())

func `==`*(a, b: FigIdx): bool {.inline.} =
  int16(a) == int16(b)

func `==`*(a, b: ImageId): bool {.inline.} =
  int(a) == int(b)

proc drawableBezier*(
    controls: openArray[vmath.Vec2], steps: uint16 = 0'u16
): DrawableOp {.inline.} =
  result = DrawableOp(kind: dkBezier, steps: steps)
  for control in controls:
    result.controls.add control.toNativeVec2()

proc cornerToU16(v: SomeNumber): uint16 {.inline.} =
  when v is SomeFloat:
    if v <= 0:
      return 0'u16
    if v >= high(uint16).float:
      return high(uint16)
    round(v).uint16
  else:
    if v <= 0:
      return 0'u16
    if v >= high(uint16):
      return high(uint16)
    v.uint16

converter toCornerRadii*[T: SomeNumber](a: array[4, T]): CornerRadii =
  for i in 0 ..< 4:
    result[DirectionCorners(i)] = cornerToU16(a[i])

converter toCornerRadii*[T: SomeNumber](a: array[DirectionCorners, T]): CornerRadii =
  for c in DirectionCorners:
    result[c] = cornerToU16(a[c])

const
  clearColor* = chroma.color(0, 0, 0, 0)
  whiteColor* = chroma.color(1, 1, 1, 1)
  blackColor* = chroma.color(0, 0, 0, 1)
  blueColor* = chroma.color(0, 0, 1, 1)

var appUiScale = 1.0'f32

proc figUiScale*(): float32 {.inline.} =
  appUiScale

proc setFigUiScale*(scale: float32) {.inline.} =
  appUiScale = scale

proc scaled*(value: bumpy.Rect): bumpy.Rect {.inline.} =
  value * appUiScale

proc descaled*(value: bumpy.Rect): bumpy.Rect {.inline.} =
  value / appUiScale

proc scaled*(value: vmath.Vec2): vmath.Vec2 {.inline.} =
  value * appUiScale

proc descaled*(value: vmath.Vec2): vmath.Vec2 {.inline.} =
  value / appUiScale

proc scaled*(value: vmath.IVec2): vmath.IVec2 {.inline.} =
  vmath.ivec2(vmath.vec2(value) * appUiScale)

proc scaled*(value: float32): float32 {.inline.} =
  value * appUiScale

proc descaled*(value: float32): float32 {.inline.} =
  value / appUiScale

proc fs*(
    font: FigFont, color: Fill = fill(rgba(0, 0, 0, 255).toNativeColor())
): FontStyle {.inline.} =
  FontStyle(font: font, color: color)

proc fsp*(font: FigFont, color: Fill, text: string): (FontStyle, string) {.inline.} =
  (FontStyle(font: font, color: color), text)

proc span*(font: FigFont, color: Fill, text: string): (FontStyle, string) {.inline.} =
  (FontStyle(font: font, color: color), text)

proc fontWithSize*(fontId: TypefaceId, size: float32): FigFont {.inline.} =
  FigFont(typefaceId: fontId, size: size)

func fontFeature*(
    tag: string, value = 1'u32, start = 0'u32, ending = uint32.high
): FontFeature {.inline.} =
  FontFeature(tag: tag, value: value, start: start, ending: ending)

func fontVariation*(tag: string, value: float32): FontVariation {.inline.} =
  FontVariation(tag: tag, value: value)

proc placeGlyphs*(
    style: FontStyle,
    glyphs: openArray[(unicode.Rune, vmath.Vec2)],
    origin = GlyphTopLeft,
): GlyphArrangement {.inline.} =
  var nativeGlyphs =
    newSeqOfCap[(figdraw_native_abi.Rune, figdraw_native_abi.Vec2)](glyphs.len)
  for (rune, pos) in glyphs:
    nativeGlyphs.add((rune.toNativeRune(), pos.toNativeVec2()))
  figdraw_native_abi.placeGlyphs(style, nativeGlyphs, origin)

template registerStaticTypeface*(
    name: static[string], path: static[string], kind: static[TypeFaceKinds] = TTF
) =
  const fontData {.gensym.} = staticRead(path)
  registerStaticTypefaceData(name, fontData, kind)

proc figDashedRoundedRectBorder*(
    box: bumpy.Rect,
    corners: CornerRadii,
    color: Fill,
    weight, dashLength, gapLength: float32,
    offset = 0.0'f32,
    cap = scButt,
    zlevel = 0.ZLevel,
): Fig {.inline.} =
  figdraw_native_abi.figDashedRoundedRectBorder(
    box.toNativeRect(),
    corners,
    color,
    weight,
    dashLength,
    gapLength,
    offset,
    cap,
    zlevel,
  )

proc figRoundedRectBorder*(
    box: bumpy.Rect,
    corners: CornerRadii,
    color: Fill,
    weight: float32,
    cap = scButt,
    zlevel = 0.ZLevel,
): Fig {.inline.} =
  figdraw_native_abi.figRoundedRectBorder(
    box.toNativeRect(), corners, color, weight, cap, zlevel
  )

proc figDottedRoundedRectBorder*(
    box: bumpy.Rect,
    corners: CornerRadii,
    color: Fill,
    weight, gapLength: float32,
    offset = 0.0'f32,
    zlevel = 0.ZLevel,
): Fig {.inline.} =
  figdraw_native_abi.figDottedRoundedRectBorder(
    box.toNativeRect(), corners, color, weight, gapLength, offset, zlevel
  )

proc typeset*(
    box: bumpy.Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement =
  figdraw_native_abi.typeset(
    box.toNativeRect(), spans, hAlign, vAlign, minContent, wrap
  )

proc toImage*(image: Image): Image {.inline.} =
  image

proc toImage*[T](image: T): Image {.inline.} =
  when compiles(image.width) and compiles(image.height) and compiles(image.data):
    result = figdraw_native_abi.newPixieImage(image.width, image.height)
    for y in 0 ..< image.height:
      for x in 0 ..< image.width:
        let pixel = image.data[y * image.width + x]
        figdraw_native_abi.setImagePixel(
          result,
          x,
          y,
          figdraw_native_abi.ColorRGBA(r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a),
        )
  else:
    {.error: "toImage requires an image with width, height, and data fields".}

proc newImage*(width, height: int): Image {.inline.} =
  newPixieImage(width, height)

proc readImage*(filePath: string): Image {.inline.} =
  readPixieImage(filePath)

proc decodeImage*(data: string): Image {.inline.} =
  decodePixieImage(data)

proc writeFile*(image: Image, filePath: string) {.inline.} =
  writePixieImage(image, filePath)

proc copy*(image: Image): Image {.inline.} =
  copyImage(image)

proc width*(image: Image): int {.inline.} =
  imageWidth(image)

proc height*(image: Image): int {.inline.} =
  imageHeight(image)

proc `[]`*(image: Image, x, y: int): chroma.ColorRGBA {.inline.} =
  imagePixel(image, x, y).toColor()

proc `[]=`*(image: Image, x, y: int, color: chroma.ColorRGBA) {.inline.} =
  setImagePixel(image, x, y, color.toNativeColor())

proc fill*(image: Image, color: chroma.ColorRGBA) {.inline.} =
  fillImage(image, color.toNativeColor())

proc loadImageRef*(filePath: string): ImageRef =
  loadFigImage(filePath)

proc loadImage*(filePath: string): ImageId {.inline.} =
  loadFigImage(filePath)

proc loadImage*(id: ImageId, image: Image) {.inline.} =
  putFigImage(id, image)

proc loadImage*[T](id: ImageId, image: T) {.inline.} =
  putFigImage(id, image.toImage())

proc imgId*(name: string): ImageId {.inline.} =
  figImageId(name)

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
  result = Window(
    width: size.x,
    height: size.y,
    titleText: title,
    fullscreen: fullscreen,
    vsync: vsync,
    resizable: resizable,
    frameless: frameless,
    transparent: transparent,
  )
  result.clipboard = Clipboard(window: result)

proc toNativePopupPlacement(value: PopupPlacement): NativePopupPlacement =
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

proc newPopupWindow*(
    parent: Window, placement: PopupPlacement, transparent = true, grab = true
): Window =
  result = Window(
    handle: newFigSiwinPopup(
      parent.handle, placement.toNativePopupPlacement(), 1024, 1.0, transparent, grab
    ),
    width: placement.size.x,
    height: placement.size.y,
    transparent: transparent,
  )
  result.clipboard = Clipboard(window: result)

proc reposition*(window: Window, placement: PopupPlacement) =
  siwinRepositionPopup(window.handle, placement.toNativePopupPlacement())

proc clipboardText*(clipboard: Clipboard): string =
  siwinClipboardText(clipboard.window.handle)

proc `clipboardText=`*(clipboard: Clipboard, value: string) =
  siwinSetClipboardText(clipboard.window.handle, value)

proc clipboardFiles*(clipboard: Clipboard): seq[string] =
  siwinClipboardFiles(clipboard.window.handle)

proc `clipboardFiles=`*(clipboard: Clipboard, value: seq[string]) =
  siwinSetClipboardFiles(clipboard.window.handle, value)

proc clipboardData*(clipboard: Clipboard, mimeType: string): string =
  siwinClipboardData(clipboard.window.handle, mimeType)

proc setClipboardData*(clipboard: Clipboard, mimeType, value: string) =
  siwinSetClipboardData(clipboard.window.handle, mimeType, value)
  if mimeType notin clipboard.mimeTypes:
    clipboard.mimeTypes.add mimeType

proc availableMimeTypes*(clipboard: Clipboard): seq[string] =
  clipboard.mimeTypes

proc setupBackend*(renderer: FigRenderer[SiwinRenderBackend], window: Window) =
  if window.handle.isNil:
    window.handle = newFigSiwinApp(
      window.width, window.height, window.titleText, renderer.atlasSize,
      renderer.pixelScale, window.fullscreen, window.vsync, 0, window.resizable,
      window.frameless, window.transparent,
    )
  renderer.window = window
  if window.autoScale:
    setFigUiScale(siwinUiScale(window.handle))

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

proc contentScale*(window: Window): float32 =
  siwinUiScale(window.handle)

proc mouse*(window: Window): Mouse =
  let pos = siwinMousePos(window.handle)
  result.pos = vmath.vec2(pos.x, pos.y)
  for button in MouseButton:
    if siwinMouseButtonPressed(window.handle, button):
      result.pressed.incl button

proc keyboard*(window: Window): Keyboard =
  for key in Key:
    if siwinKeyPressed(window.handle, key):
      result.pressed.incl key
  for modifier in ModifierKey:
    if siwinModifierPressed(window.handle, modifier):
      result.modifiers.incl modifier

proc configureUiScale*(window: Window, envVar = "HDI"): bool =
  let configuredScale = getEnv(envVar)
  if configuredScale.len == 0:
    window.autoScale = true
    if not window.handle.isNil:
      setFigUiScale(window.contentScale())
    true
  else:
    window.autoScale = false
    setFigUiScale(configuredScale.parseFloat().float32)
    false

proc refreshUiScale*(window: Window, autoScale: bool) =
  siwinRefreshUiScale(window.handle)
  if autoScale:
    setFigUiScale(window.contentScale())

proc backingSize*(window: Window): vmath.IVec2 =
  let size = siwinBackingSize(window.handle)
  ivec2(size.w, size.h)

proc size*(window: Window): vmath.IVec2 =
  let size = siwinWindowSize(window.handle)
  ivec2(size.w, size.h)

proc `size=`*(window: Window, value: vmath.IVec2) =
  window.installEventCallbacks()
  siwinSetWindowSize(window.handle, value.x, value.y)

proc pos*(window: Window): vmath.IVec2 =
  let pos = siwinWindowPos(window.handle)
  ivec2(pos.x, pos.y)

proc `pos=`*(window: Window, value: vmath.IVec2) =
  siwinSetWindowPos(window.handle, value.x, value.y)

proc logicalSize*(window: Window): vmath.Vec2 =
  let
    size = window.backingSize()
    scale = max(window.contentScale(), 0.0001'f32)
  vec2(size.x.float32 / scale, size.y.float32 / scale)

proc `title=`*(window: Window, value: string) =
  window.titleText = value
  siwinSetTitle(window.handle, value)

proc visible*(window: Window): bool =
  siwinIsVisible(window.handle)

proc `visible=`*(window: Window, value: bool) =
  siwinSetVisible(window.handle, value)

proc focused*(window: Window): bool =
  siwinIsFocused(window.handle)

proc fullscreen*(window: Window): bool =
  siwinIsFullscreen(window.handle)

proc `fullscreen=`*(window: Window, value: bool) =
  siwinSetFullscreen(window.handle, value)

proc maximized*(window: Window): bool =
  siwinIsMaximized(window.handle)

proc `maximized=`*(window: Window, value: bool) =
  siwinSetMaximized(window.handle, value)

proc minimized*(window: Window): bool =
  siwinIsMinimized(window.handle)

proc `minimized=`*(window: Window, value: bool) =
  siwinSetMinimized(window.handle, value)

proc resizable*(window: Window): bool =
  siwinIsResizable(window.handle)

proc `resizable=`*(window: Window, value: bool) =
  siwinSetResizable(window.handle, value)

proc frameless*(window: Window): bool =
  siwinIsFrameless(window.handle)

proc `frameless=`*(window: Window, value: bool) =
  siwinSetFrameless(window.handle, value)

proc transparent*(window: Window): bool =
  siwinIsTransparent(window.handle)

proc `icon=`*(window: Window, image: Image) {.inline.} =
  figdraw_native_abi.siwinSetIcon(window.handle, image)

proc opened*(window: Window): bool =
  not window.handle.isNil and opened(window.handle)

proc closed*(window: Window): bool =
  not window.opened()

proc presentNow*(window: Window) =
  redraw(window.handle)

proc close*(window: Window) =
  if not window.handle.isNil:
    close(window.handle)

proc firstStep*(window: Window, makeVisible = true) =
  window.installEventCallbacks()
  firstStep(window.handle, makeVisible)
  window.wasOpened = window.opened
  window.lastMouse = window.mouse()
  window.lastKeyboard = window.keyboard()
  window.lastPos = window.pos()
  window.lastFocused = window.focused()
  window.lastFullscreen = window.fullscreen()
  window.lastMaximized = window.maximized()
  window.lastFrameless = window.frameless()
  window.lastPopupOpen = siwinPopupOpen(window.handle)
  window.pollReady = true

proc redraw*(window: Window) =
  redraw(window.handle)

proc makeCurrent*(window: Window) =
  makeCurrent(window.handle)

proc step*(window: Window) =
  window.installEventCallbacks()
  step(window.handle)

  let
    currentMouse = window.mouse()
    currentKeyboard = window.keyboard()
    currentPos = window.pos()
    currentFocused = window.focused()
    currentFullscreen = window.fullscreen()
    currentMaximized = window.maximized()
    currentFrameless = window.frameless()
    currentPopupOpen = siwinPopupOpen(window.handle)

  if window.pollReady:
    if currentMouse.pos != window.lastMouse.pos and
        window.eventsHandler.onMouseMove != nil:
      window.eventsHandler.onMouseMove(
        MouseMoveEvent(
          window: window,
          pos: currentMouse.pos,
          kind: if currentMouse.pressed == {}: move else: moveWhileDragging,
        )
      )

    if window.eventsHandler.onMouseButton != nil:
      for button in MouseButton:
        let
          wasPressed = button in window.lastMouse.pressed
          isPressed = button in currentMouse.pressed
        if wasPressed != isPressed:
          window.eventsHandler.onMouseButton(
            MouseButtonEvent(window: window, button: button, pressed: isPressed)
          )

    if currentPos != window.lastPos and window.eventsHandler.onWindowMove != nil:
      window.eventsHandler.onWindowMove(
        WindowMoveEvent(window: window, pos: currentPos)
      )

    template dispatchState(kindValue, currentValue, previousValue: untyped) =
      if currentValue != previousValue and window.eventsHandler.onStateBoolChanged != nil:
        window.eventsHandler.onStateBoolChanged(
          StateBoolChangedEvent(
            window: window, value: currentValue, kind: kindValue, isExternal: true
          )
        )

    dispatchState(StateBoolChangedEventKind.focus, currentFocused, window.lastFocused)
    dispatchState(
      StateBoolChangedEventKind.fullscreen, currentFullscreen, window.lastFullscreen
    )
    dispatchState(
      StateBoolChangedEventKind.maximized, currentMaximized, window.lastMaximized
    )
    dispatchState(
      StateBoolChangedEventKind.frameless, currentFrameless, window.lastFrameless
    )

    if window.lastPopupOpen and not currentPopupOpen and
        window.eventsHandler.onPopupDone != nil:
      window.eventsHandler.onPopupDone(
        PopupEvent(window: window, reason: pdrCompositorDismissed)
      )

  window.lastMouse = currentMouse
  window.lastKeyboard = currentKeyboard
  window.lastPos = currentPos
  window.lastFocused = currentFocused
  window.lastFullscreen = currentFullscreen
  window.lastMaximized = currentMaximized
  window.lastFrameless = currentFrameless
  window.lastPopupOpen = currentPopupOpen
  window.pollReady = true

  let isOpened = window.opened
  if window.wasOpened and not isOpened and window.eventsHandler.onClose != nil:
    window.eventsHandler.onClose(CloseEvent(window: window))
  window.wasOpened = isOpened

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  discard renderer

proc renderFrame*(
    renderer: FigRenderer[SiwinRenderBackend],
    renders: var Renders,
    size: vmath.Vec2,
    clearMain = true,
    clearColor = whiteColor,
) =
  renderFrame(
    renderer.window.handle, renders, size.x, size.y, clearMain, clearColor.r,
    clearColor.g, clearColor.b, clearColor.a,
  )

proc endFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  discard renderer

proc backendName*(renderer: FigRenderer[SiwinRenderBackend]): string =
  siwinBackendName(renderer.window.handle)

proc backendKind*(renderer: FigRenderer[SiwinRenderBackend]): RendererBackendKind =
  siwinBackendKind(renderer.window.handle)

proc setTextLcdFiltering*(renderer: FigRenderer[SiwinRenderBackend], enabled: bool) =
  setTextLcdFiltering(renderer.window.handle, enabled)

proc textLcdFiltering*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  textLcdFiltering(renderer.window.handle)

proc setTextSubpixelPositioning*(
    renderer: FigRenderer[SiwinRenderBackend], enabled: bool
) =
  setTextSubpixelPositioning(renderer.window.handle, enabled)

proc textSubpixelPositioning*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  textSubpixelPositioning(renderer.window.handle)

proc setTextSubpixelGlyphVariants*(
    renderer: FigRenderer[SiwinRenderBackend], enabled: bool
) =
  setTextSubpixelGlyphVariants(renderer.window.handle, enabled)

proc textSubpixelGlyphVariants*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  textSubpixelGlyphVariants(renderer.window.handle)

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: native dynlib + " & suffix

proc siwinWindowTitle*(
    renderer: FigRenderer[SiwinRenderBackend],
    window: Window,
    suffix = "Siwin RenderList",
): string =
  discard window
  "figdraw: " & renderer.backendName() & " + " & suffix
