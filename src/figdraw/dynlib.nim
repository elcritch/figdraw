## FigDraw conveniences and shared-type converters over the generated native ABI.

import std/[tables, unicode]
import pkg/bumpy as bumpy
import pkg/chroma as chroma
from pkg/pixie import Image
import pkg/vmath as vmath
import figdraw_native_abi
from figdraw/common/fonttypes import fontVariation
import figdraw/extras/systemfonttypes as systemfonttypes
from figdraw/extras/systemfonttypes import
  SystemTypeface, initSystemTypefaceFile, initSystemTypeface

when not defined(gcArc):
  {.error: "figdraw/dynlib requires --mm:arc to match the native library".}

export tables, bumpy, chroma, vmath
export Image
export figdraw_native_abi except
  ColorRGBA, Vec2, IVec2, Mat4, Rune, FigSelectionRange, SystemTypefaceFile,
  placeGlyphs, toRunes, `[]`, newSiwinWindow
export
  SystemTypeface, systemfonttypes.SystemTypefaceFile, initSystemTypefaceFile,
  initSystemTypeface

proc systemFontDirs*(): seq[string] {.inline.} =
  figdraw_native_abi.systemFontDirs(figdraw_native_abi.detectDisplayServer())

proc systemFontFiles*(): seq[string] {.inline.} =
  figdraw_native_abi.systemFontFiles(figdraw_native_abi.detectDisplayServer())

const
  UseVulkanBackend* = false
  UseMetalBackend* = false
  ShadowCount* = 4
  DefaultDrawableBezierSteps* = 48'u16
  DefaultDrawableArcSteps* = 48'u16

const figdrawTextBackend* {.strdefine.} =
  when defined(feature.figdraw.textBackendHarfbuzz):
    {.warning: "HARFBUZZ!!!!!".}
    "harfbuzz"
  else:
    {.warning: "PIXIE!!!!!".}
    "pixie"

type
  ImageRef* = ImageId

  DirectionCorners* = enum
    dcTopLeft
    dcTopRight
    dcBottomLeft
    dcBottomRight

  CornerRadii2D*[T] = object
    x*, y*: array[DirectionCorners, T]

  SiwinRenderBackend* = object

  SiwinPresentationTarget* = object

  FigRenderer*[BackendState] = ref object
    atlasSize: int
    pixelScale: float32
    handle: NativeSiwinApp

converter nilToImageRef*(value: typeof(nil)): ImageRef =
  discard value
  default(ImageRef)

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

converter toNativeIVec2*(value: vmath.IVec2): figdraw_native_abi.IVec2 {.inline.} =
  cast[figdraw_native_abi.IVec2](value)

converter toIVec2*(value: figdraw_native_abi.IVec2): vmath.IVec2 {.inline.} =
  cast[vmath.IVec2](value)

converter toCursor*(value: BuiltinCursor): Cursor {.inline.} =
  Cursor(kind: CursorKind.builtin, builtin: value)

converter toNativeMat4*(value: vmath.Mat4): figdraw_native_abi.Mat4 {.inline.} =
  cast[figdraw_native_abi.Mat4](value)

converter toMat4*(value: figdraw_native_abi.Mat4): vmath.Mat4 {.inline.} =
  cast[vmath.Mat4](value)

converter toNativeRune*(value: unicode.Rune): figdraw_native_abi.Rune {.inline.} =
  cast[figdraw_native_abi.Rune](value)

converter toRune*(value: figdraw_native_abi.Rune): unicode.Rune {.inline.} =
  cast[unicode.Rune](value)

proc toRunes*(runes: figdraw_native_abi.Utf8Runes): seq[unicode.Rune] =
  let nativeRunes = figdraw_native_abi.toRunes(runes)
  result = newSeqOfCap[unicode.Rune](nativeRunes.len)
  for rune in nativeRunes:
    result.add rune.toRune()

converter toRuneSequence*(runes: figdraw_native_abi.Utf8Runes): seq[unicode.Rune] =
  runes.toRunes()

converter toUtf8Runes*(runes: seq[unicode.Rune]): figdraw_native_abi.Utf8Runes =
  var nativeRunes = newSeqOfCap[figdraw_native_abi.Rune](runes.len)
  for rune in runes:
    nativeRunes.add rune.toNativeRune()
  figdraw_native_abi.utf8RunesFromRunes(nativeRunes)

proc `[]`*(runes: figdraw_native_abi.Utf8Runes, index: int): unicode.Rune =
  figdraw_native_abi.`[]`(runes, index).toRune()

proc `[]`*(
    runes: figdraw_native_abi.Utf8Runes, slice: Slice[int]
): figdraw_native_abi.Utf8Runes =
  figdraw_native_abi.`[]`(runes, cast[figdraw_native_abi.IntSlice](slice))

iterator items*(runes: figdraw_native_abi.Utf8Runes): unicode.Rune =
  for rune in figdraw_native_abi.stringValue(runes).runes:
    yield rune

iterator pairs*(
    runes: figdraw_native_abi.Utf8Runes
): tuple[index: int, value: unicode.Rune] =
  var index = 0
  for rune in figdraw_native_abi.stringValue(runes).runes:
    yield (index, rune)
    inc index

func `==`*(a, b: figdraw_native_abi.Utf8Runes): bool {.inline.} =
  figdraw_native_abi.utf8RunesEqual(a, b)

func `==`*(a: figdraw_native_abi.Utf8Runes, b: openArray[unicode.Rune]): bool =
  var nativeRunes = newSeqOfCap[figdraw_native_abi.Rune](b.len)
  for rune in b:
    nativeRunes.add rune.toNativeRune()
  figdraw_native_abi.utf8RunesEqualRunes(a, nativeRunes)

func `==`*(a: openArray[unicode.Rune], b: figdraw_native_abi.Utf8Runes): bool =
  b == a

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

proc typeset*(
    box: bumpy.Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  figdraw_native_abi.typesetStyled(box, spans, hAlign, vAlign, minContent, wrap)

proc typesetForMeasurement*(
    box: bumpy.Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  figdraw_native_abi.typesetStyledForMeasurement(
    box, spans, hAlign, vAlign, minContent, wrap
  )

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
    result[i] = cornerToU16(a[i])

converter toCornerRadii*[T: SomeNumber](a: array[DirectionCorners, T]): CornerRadii =
  for c in DirectionCorners:
    result[c.ord] = cornerToU16(a[c])

func initCornerRadii2D*[T](radii: array[DirectionCorners, T]): CornerRadii2D[T] =
  CornerRadii2D[T](x: radii, y: radii)

converter toCornerRadii2D*[T](radii: array[DirectionCorners, T]): CornerRadii2D[T] =
  initCornerRadii2D(radii)

func initCornerRadii2D*[T](x, y: array[DirectionCorners, T]): CornerRadii2D[T] =
  CornerRadii2D[T](x: x, y: y)

func isCircular*[T](radii: CornerRadii2D[T]): bool =
  for corner in DirectionCorners:
    if radii.x[corner] != radii.y[corner]:
      return false
  true

const
  clearColor* = chroma.color(0, 0, 0, 0)
  whiteColor* = chroma.color(1, 1, 1, 1)
  blackColor* = chroma.color(0, 0, 0, 1)
  blueColor* = chroma.color(0, 0, 1, 1)

proc scaled*(value: bumpy.Rect): bumpy.Rect {.inline.} =
  value * figUiScale()

proc descaled*(value: bumpy.Rect): bumpy.Rect {.inline.} =
  value / figUiScale()

proc scaled*(value: vmath.Vec2): vmath.Vec2 {.inline.} =
  value * figUiScale()

proc descaled*(value: vmath.Vec2): vmath.Vec2 {.inline.} =
  value / figUiScale()

proc scaled*(value: vmath.IVec2): vmath.IVec2 {.inline.} =
  vmath.ivec2(vmath.vec2(value) * figUiScale())

proc scaled*(value: float32): float32 {.inline.} =
  value * figUiScale()

proc descaled*(value: float32): float32 {.inline.} =
  value / figUiScale()

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

proc loadTypeface*(file: systemfonttypes.SystemTypefaceFile): TypefaceId =
  figdraw_native_abi.loadTypeface(
    figdraw_native_abi.SystemTypefaceFile(path: file.path, faceIndex: file.faceIndex)
  )

proc fontWithSize*(typeface: SystemTypeface, size: float32): FigFont =
  ## Loads an exact installed typeface through the native ABI.
  result = loadTypeface(typeface.file).fontWithSize(size)
  result.variations = newSeqOfCap[FontVariation](typeface.variations.len)
  for variation in typeface.variations:
    result.variations.add FontVariation(tag: variation.tag, value: variation.value)

func fontFeature*(
    tag: string, value = 1'u32, start = 0'u32, ending = uint32.high
): FontFeature {.inline.} =
  FontFeature(tag: tag, value: value, start: start, ending: ending)

proc placeGlyphs*(
    style: FontStyle,
    glyphs: openArray[(unicode.Rune, vmath.Vec2)],
    origin = GlyphTopLeft,
): GlyphArrangement {.inline.} =
  var nativeGlyphs =
    newSeqOfCap[(figdraw_native_abi.Rune, figdraw_native_abi.Vec2)](glyphs.len)
  for (rune, pos) in glyphs:
    nativeGlyphs.add((rune.toNativeRune(), pos.toNativeVec2()))
  figdraw_native_abi.placeStyledGlyphs(style, nativeGlyphs, origin)

template registerStaticTypeface*(
    name: static[string], path: static[string], kind: static[TypeFaceKinds] = TTF
) =
  const fontData {.gensym.} = staticRead(path)
  registerStaticTypefaceData(name, fontData, kind)

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

proc replaceImage*(id: ImageId, image: Image) {.inline.} =
  replaceFigImage(id, image)

proc replaceImage*[T](id: ImageId, image: T) {.inline.} =
  replaceFigImage(id, image.toImage())

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
  ## Creates the producer's platform window without importing Siwin locally.
  figdraw_native_abi.newSiwinWindow(
    size.toNativeIVec2(),
    fullscreen,
    title,
    vsync,
    msaa,
    resizable,
    frameless,
    transparent,
  )

proc newPopupWindow*(
    parent: Window, placement: PopupPlacement, transparent = true, grab = true
): Window =
  figdraw_native_abi.newSiwinPopupWindow(parent, placement, transparent, grab)

proc setupBackend*(renderer: FigRenderer[SiwinRenderBackend], window: Window) =
  renderer.handle = newFigSiwinApp(window, renderer.atlasSize, renderer.pixelScale)

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

proc nativeWindowKey*(window: Window): pointer {.inline.} =
  cast[pointer](window)

proc startInteractiveMove*(window: Window, pos: vmath.Vec2) {.inline.} =
  siwinStartInteractiveMove(window, pos.toNativeVec2())

proc startInteractiveResize*(window: Window, edge: Edge, pos: vmath.Vec2) {.inline.} =
  siwinStartInteractiveResize(window, edge, pos.toNativeVec2())

proc showWindowMenu*(window: Window, pos: vmath.Vec2) {.inline.} =
  siwinShowWindowMenu(window, pos.toNativeVec2())

proc `icon=`*(window: Window, image: Image) {.inline.} =
  siwinSetIcon(window, image)

template `vsync=`*(window: Window, value: bool) =
  figdraw_native_abi.`vsync=`(window, value, false)

template firstStep*(window: Window) =
  figdraw_native_abi.firstStep(window, true)

template configureUiScale*(window: Window): bool =
  figdraw_native_abi.configureUiScale(window, "HDI")

proc `[]`*(clipboard: Clipboard, mimeType: string): string {.inline.} =
  figdraw_native_abi.`[]`(clipboard, mimeType)

proc presentationTarget*(
    renderer: FigRenderer[SiwinRenderBackend]
): SiwinPresentationTarget =
  discard renderer

proc updatePresentationTarget*(target: SiwinPresentationTarget, window: Window) =
  discard target
  discard window

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
    renderer.handle, renders, size.x, size.y, clearMain, clearColor.r, clearColor.g,
    clearColor.b, clearColor.a,
  )

proc endFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  discard renderer

proc backendName*(renderer: FigRenderer[SiwinRenderBackend]): string =
  siwinBackendName(renderer.handle)

proc backendKind*(renderer: FigRenderer[SiwinRenderBackend]): RendererBackendKind =
  siwinBackendKind(renderer.handle)

proc setTextLcdFiltering*(renderer: FigRenderer[SiwinRenderBackend], enabled: bool) =
  setTextLcdFiltering(renderer.handle, enabled)

proc textLcdFiltering*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  textLcdFiltering(renderer.handle)

proc setTextSubpixelPositioning*(
    renderer: FigRenderer[SiwinRenderBackend], enabled: bool
) =
  setTextSubpixelPositioning(renderer.handle, enabled)

proc textSubpixelPositioning*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  textSubpixelPositioning(renderer.handle)

proc setTextSubpixelGlyphVariants*(
    renderer: FigRenderer[SiwinRenderBackend], enabled: bool
) =
  setTextSubpixelGlyphVariants(renderer.handle, enabled)

proc textSubpixelGlyphVariants*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  textSubpixelGlyphVariants(renderer.handle)

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: " & siwinBackendName() & " + " & suffix

proc siwinWindowTitle*(
    renderer: FigRenderer[SiwinRenderBackend],
    window: Window,
    suffix = "Siwin RenderList",
): string =
  discard window
  "figdraw: " & renderer.backendName() & " + " & suffix
