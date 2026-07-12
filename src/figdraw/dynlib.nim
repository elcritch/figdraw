## Source-compatible FigDraw/Siwin facade backed by the native Nim dynamic library.

import std/[os, strutils, tables, unicode]
import pkg/bumpy as bumpy
import pkg/chroma as chroma
import pkg/vmath as vmath
import figdraw_native_abi

export tables, bumpy, chroma, vmath
export figdraw_native_abi except
  Rect, ColorRGBA, ColorRGBX, Image, Vec2, Mat4, Rune, FigSelectionRange,
  applyImageOpacity, copyImage, cropImage, decodePixieImage, fillImage,
  figDashedRoundedRectBorder, figDottedRoundedRectBorder, figRoundedRectBorder,
  flipImageHorizontal, flipImageVertical, imageHeight, imageIsOpaque,
  imageIsTransparent, imagePixel, imageWidth, invertImage, newPixieImage, placeGlyphs,
  putFigImage, readPixieImage, resizeImage, rotateImage90, setImagePixel, siwinSetIcon,
  typeset, writePixieImage

const
  UseVulkanBackend* = false
  UseMetalBackend* = false
  ShadowCount* = 4
  DefaultDrawableBezierSteps* = 48'u16
  DefaultDrawableArcSteps* = 48'u16
  figdrawTextBackend* {.strdefine.} = "pixie"

type
  Image* = object
    handle: figdraw_native_abi.Image

  ImageRef* = ImageId

  SiwinRenderBackend* = object

  Window* = ref object
    handle: NativeSiwinApp
    eventsHandler*: WindowEventsHandler
    wasOpened: bool
    escapePressed: bool
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

proc installEventCallbacks(window: Window) =
  siwinSetEventCallbacks(
    window.handle,
    cast[pointer](window),
    cast[pointer](dispatchNativeResize),
    cast[pointer](dispatchNativeRender),
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

converter toNativeColor*(
    value: chroma.ColorRGBX
): figdraw_native_abi.ColorRGBX {.inline.} =
  cast[figdraw_native_abi.ColorRGBX](value)

converter toColor*(value: figdraw_native_abi.ColorRGBX): chroma.ColorRGBX {.inline.} =
  cast[chroma.ColorRGBX](value)

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

converter toFill*(value: chroma.ColorRGBA): Fill {.inline.} =
  fill(value.toNativeColor())

converter toFill*(value: chroma.Color): Fill {.inline.} =
  fill(value.rgba().toNativeColor())

proc drawableLine*(a, b: vmath.Vec2): DrawableOp {.inline.} =
  DrawableOp(kind: dkLine, a: a.toNativeVec2(), b: b.toNativeVec2())

proc drawableLine*(x1, y1, x2, y2: float32): DrawableOp {.inline.} =
  drawableLine(vmath.vec2(x1, y1), vmath.vec2(x2, y2))

proc drawableCircle*(center: vmath.Vec2, radius: float32): DrawableOp {.inline.} =
  DrawableOp(kind: dkCircle, center: center.toNativeVec2(), radius: radius)

proc drawableCircle*(x, y, radius: float32): DrawableOp {.inline.} =
  drawableCircle(vmath.vec2(x, y), radius)

proc drawableRect*(
    box: bumpy.Rect, corners: CornerRadii = [0'u16, 0'u16, 0'u16, 0'u16]
): DrawableOp {.inline.} =
  DrawableOp(kind: dkRectangle, box: box.toNativeRect(), corners: corners)

proc drawableBezier*(
    controls: openArray[vmath.Vec2], steps: uint16 = 0'u16
): DrawableOp {.inline.} =
  result = DrawableOp(kind: dkBezier, steps: steps)
  for control in controls:
    result.controls.add control.toNativeVec2()

proc drawableBezier*(
    p0, p1, p2: vmath.Vec2, steps: uint16 = 0'u16
): DrawableOp {.inline.} =
  drawableBezier([p0, p1, p2], steps)

proc drawableBezier*(
    p0, p1, p2, p3: vmath.Vec2, steps: uint16 = 0'u16
): DrawableOp {.inline.} =
  drawableBezier([p0, p1, p2, p3], steps)

proc drawableArc*(
    center: vmath.Vec2, radius, startAngle, sweepAngle: float32, steps: uint16 = 0'u16
): DrawableOp {.inline.} =
  DrawableOp(
    kind: dkArc,
    arcCenter: center.toNativeVec2(),
    arcRadius: radius,
    startAngle: startAngle,
    sweepAngle: sweepAngle,
    arcSteps: steps,
  )

proc drawableArc*(
    x, y, radius, startAngle, sweepAngle: float32, steps: uint16 = 0'u16
): DrawableOp {.inline.} =
  drawableArc(vmath.vec2(x, y), radius, startAngle, sweepAngle, steps)

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

proc wrapImage(handle: figdraw_native_abi.Image): Image {.inline.} =
  Image(handle: handle)

proc toImage*(image: Image): Image {.inline.} =
  image

proc toImage*[T](image: T): Image {.inline.} =
  when compiles(image.width) and compiles(image.height) and compiles(image.data):
    Image(handle: cast[figdraw_native_abi.Image](image))
  else:
    {.error: "toImage requires an image with width, height, and data fields".}

proc isNil*(image: Image): bool {.inline.} =
  image.handle.isNil

proc newPixieImage*(width, height: int): Image {.inline.} =
  wrapImage(figdraw_native_abi.newPixieImage(width, height))

proc newImage*(width, height: int): Image {.inline.} =
  newPixieImage(width, height)

proc readPixieImage*(filePath: string): Image {.inline.} =
  wrapImage(figdraw_native_abi.readPixieImage(filePath))

proc readImage*(filePath: string): Image {.inline.} =
  readPixieImage(filePath)

proc decodePixieImage*(data: string): Image {.inline.} =
  wrapImage(figdraw_native_abi.decodePixieImage(data))

proc decodeImage*(data: string): Image {.inline.} =
  decodePixieImage(data)

proc writePixieImage*(image: Image, filePath: string) {.inline.} =
  figdraw_native_abi.writePixieImage(image.handle, filePath)

proc writeFile*(image: Image, filePath: string) {.inline.} =
  writePixieImage(image, filePath)

proc copyImage*(image: Image): Image {.inline.} =
  wrapImage(figdraw_native_abi.copyImage(image.handle))

proc copy*(image: Image): Image {.inline.} =
  copyImage(image)

proc resizeImage*(image: Image, width, height: int): Image {.inline.} =
  wrapImage(figdraw_native_abi.resizeImage(image.handle, width, height))

proc resize*(image: Image, width, height: int): Image {.inline.} =
  resizeImage(image, width, height)

proc cropImage*(image: Image, x, y, width, height: int): Image {.inline.} =
  wrapImage(figdraw_native_abi.cropImage(image.handle, x, y, width, height))

proc subImage*(image: Image, x, y, width, height: int): Image {.inline.} =
  cropImage(image, x, y, width, height)

proc imageWidth*(image: Image): int {.inline.} =
  figdraw_native_abi.imageWidth(image.handle)

proc width*(image: Image): int {.inline.} =
  imageWidth(image)

proc imageHeight*(image: Image): int {.inline.} =
  figdraw_native_abi.imageHeight(image.handle)

proc height*(image: Image): int {.inline.} =
  imageHeight(image)

proc imagePixel*(image: Image, x, y: int): chroma.ColorRGBA {.inline.} =
  figdraw_native_abi.imagePixel(image.handle, x, y).toColor()

proc `[]`*(image: Image, x, y: int): chroma.ColorRGBA {.inline.} =
  imagePixel(image, x, y)

proc setImagePixel*(image: Image, x, y: int, color: chroma.ColorRGBA) {.inline.} =
  figdraw_native_abi.setImagePixel(image.handle, x, y, color.toNativeColor())

proc `[]=`*(image: Image, x, y: int, color: chroma.ColorRGBA) {.inline.} =
  setImagePixel(image, x, y, color)

proc fillImage*(image: Image, color: chroma.ColorRGBA) {.inline.} =
  figdraw_native_abi.fillImage(image.handle, color.toNativeColor())

proc fill*(image: Image, color: chroma.ColorRGBA) {.inline.} =
  fillImage(image, color)

proc flipImageHorizontal*(image: Image) {.inline.} =
  figdraw_native_abi.flipImageHorizontal(image.handle)

proc flipHorizontal*(image: Image) {.inline.} =
  flipImageHorizontal(image)

proc flipImageVertical*(image: Image) {.inline.} =
  figdraw_native_abi.flipImageVertical(image.handle)

proc flipVertical*(image: Image) {.inline.} =
  flipImageVertical(image)

proc rotateImage90*(image: Image) {.inline.} =
  figdraw_native_abi.rotateImage90(image.handle)

proc rotate90*(image: Image) {.inline.} =
  rotateImage90(image)

proc applyImageOpacity*(image: Image, opacity: float32) {.inline.} =
  figdraw_native_abi.applyImageOpacity(image.handle, opacity)

proc applyOpacity*(image: Image, opacity: float32) {.inline.} =
  applyImageOpacity(image, opacity)

proc invertImage*(image: Image) {.inline.} =
  figdraw_native_abi.invertImage(image.handle)

proc invert*(image: Image) {.inline.} =
  invertImage(image)

proc imageIsTransparent*(image: Image): bool {.inline.} =
  figdraw_native_abi.imageIsTransparent(image.handle)

proc isTransparent*(image: Image): bool {.inline.} =
  imageIsTransparent(image)

proc imageIsOpaque*(image: Image): bool {.inline.} =
  figdraw_native_abi.imageIsOpaque(image.handle)

proc isOpaque*(image: Image): bool {.inline.} =
  imageIsOpaque(image)

proc loadImageRef*(filePath: string): ImageRef =
  loadFigImage(filePath)

proc loadImage*(filePath: string): ImageId {.inline.} =
  loadFigImage(filePath)

proc putFigImage*(id: ImageId, image: Image) {.inline.} =
  figdraw_native_abi.putFigImage(id, image.handle)

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

proc siwinSetIcon*(appHandle: NativeSiwinApp, image: Image) {.inline.} =
  figdraw_native_abi.siwinSetIcon(appHandle, image.handle)

proc `icon=`*(window: Window, image: Image) {.inline.} =
  siwinSetIcon(window.handle, image)

proc opened*(window: Window): bool =
  not window.handle.isNil and opened(window.handle)

proc close*(window: Window) =
  if not window.handle.isNil:
    close(window.handle)

proc firstStep*(window: Window, makeVisible = true) =
  window.installEventCallbacks()
  firstStep(window.handle, makeVisible)
  window.wasOpened = window.opened

proc redraw*(window: Window) =
  redraw(window.handle)

proc makeCurrent*(window: Window) =
  makeCurrent(window.handle)

proc step*(window: Window) =
  window.installEventCallbacks()
  step(window.handle)

  let escapePressed = siwinKeyPressed(window.handle, escape)
  if escapePressed != window.escapePressed and window.eventsHandler.onKey != nil:
    window.eventsHandler.onKey(
      KeyEvent(window: window, key: escape, pressed: escapePressed)
    )
  window.escapePressed = escapePressed

  let isOpened = window.opened
  if window.wasOpened and not isOpened and window.eventsHandler.onClose != nil:
    window.eventsHandler.onClose(CloseEvent(window: window))
  window.wasOpened = isOpened

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  discard renderer

proc renderFrame*(
    renderer: FigRenderer[SiwinRenderBackend],
    renders: Renders,
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
