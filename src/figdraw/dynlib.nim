## FigDraw conveniences over the generated native ABI and shared Nim types.

import std/[macros, options, tables, unicode]
import pkg/bumpy as bumpy
import pkg/chroma as chroma
from pkg/pixie import Image
import pkg/vmath as vmath
import figdraw_native_abi
from figdraw/extras/systemfonttypes import initSystemTypefaceFile, initSystemTypeface

when not defined(gcArc):
  {.error: "figdraw/dynlib requires --mm:arc to match the native library".}

export options, tables, bumpy, chroma, vmath
export Image
export figdraw_native_abi except placeGlyphs, newSiwinWindow, newFigRenderer, `[]`

macro exportNativeIndexers(indexers: typed): untyped =
  ## Re-export ABI symbols directly, except the image getter converted below.
  result = newNimNode(nnkExportStmt)
  for indexer in indexers:
    let firstParamType = indexer.getTypeImpl()[0][1][^2]
    if not firstParamType.sameType(bindSym("Image")):
      result.add indexer

exportNativeIndexers(figdraw_native_abi.`[]`)

export initSystemTypefaceFile, initSystemTypeface

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

  CornerRadii2D*[T] = object
    x*, y*: array[DirectionCorners, T]

  FigRenderer*[BackendState] = ref object
    atlasSize: int
    pixelScale: float32
    backendState: BackendState
    native: SiwinRenderer
    window: Window
    autoScale: bool

converter toSiwinRenderer*(renderer: FigRenderer[SiwinRenderBackend]): SiwinRenderer =
  ## Exposes the typed renderer for direct native renderer operations.
  renderer.native

converter nilToImageRef*(value: typeof(nil)): ImageRef =
  discard value
  default(ImageRef)

converter toCursor*(value: BuiltinCursor): Cursor {.inline.} =
  Cursor(kind: CursorKind.builtin, builtin: value)

converter toOptionalPosition*(value: vmath.Vec2): Option[vmath.Vec2] {.inline.} =
  some(value)

converter toPixelBuffer*(image: Image): PixelBuffer {.inline.} =
  ## Borrows the image's premultiplied pixels; keep the image alive while using
  ## the returned buffer. Nil or empty images yield an empty buffer.
  if not image.isNil and image.data.len > 0:
    result = PixelBuffer(
      data: image.data[0].addr,
      size: ivec2(image.width.int32, image.height.int32),
      format: rgbx_32bit,
    )

converter toRuneSequence*(runes: figdraw_native_abi.Utf8Runes): seq[unicode.Rune] =
  runes.toRunes()

converter toUtf8Runes*(runes: seq[unicode.Rune]): figdraw_native_abi.Utf8Runes =
  figdraw_native_abi.initUtf8Runes(runes)

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
  figdraw_native_abi.utf8RunesEqualRunes(a, b)

func `==`*(a: openArray[unicode.Rune], b: figdraw_native_abi.Utf8Runes): bool =
  b == a

converter toFill*(value: chroma.ColorRGBA): Fill {.inline.} =
  fill(value)

converter toFill*(value: chroma.Color): Fill {.inline.} =
  fill(value.rgba())

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

proc fs*(font: FigFont): FontStyle {.inline.} =
  ## Supplies the source API's default fill omitted from generated bindings.
  figdraw_native_abi.fs(font, fill(rgba(0, 0, 0, 255)))

func fontFeature*(
    tag: string, value = 1'u32, start = 0'u32, ending = uint32.high
): FontFeature {.inline.} =
  FontFeature(tag: tag, value: value, start: start, ending: ending)

proc placeGlyphs*(
    style: FontStyle,
    glyphs: openArray[(unicode.Rune, vmath.Vec2)],
    origin = GlyphTopLeft,
): GlyphArrangement {.inline.} =
  figdraw_native_abi.placeStyledGlyphs(style, glyphs, origin)

template registerStaticTypeface*(
    name: static[string], path: static[string], kind: static[TypeFaceKinds] = TTF
) =
  const fontData {.gensym.} = staticRead(path)
  registerStaticTypefaceData(name, fontData, kind)

proc toImage*(image: Image): Image {.inline.} =
  image

proc toImage*[T](image: T): Image {.inline.} =
  when compiles(image.width) and compiles(image.height) and compiles(image.data):
    result = figdraw_native_abi.newImage(image.width, image.height)
    for y in 0 ..< image.height:
      for x in 0 ..< image.width:
        let pixel = image.data[y * image.width + x]
        figdraw_native_abi.`[]=`(
          result,
          x,
          y,
          figdraw_native_abi.ColorRGBA(r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a),
        )
  else:
    {.error: "toImage requires an image with width, height, and data fields".}

proc `[]`*(image: Image, x, y: int): chroma.ColorRGBA {.inline.} =
  ## Keeps FigDraw's straight-alpha view over Pixie's premultiplied pixels.
  figdraw_native_abi.`[]`(image, x, y).rgba()

proc loadImageRef*(filePath: string): ImageRef =
  loadFigImage(filePath)

proc loadImage*[T](id: ImageId, image: T) {.inline.} =
  figdraw_native_abi.loadImage(id, image.toImage())

proc replaceImage*[T](id: ImageId, image: T) {.inline.} =
  figdraw_native_abi.replaceImage(id, image.toImage())

proc imageStyle*(image: ImageRef): ImageStyle =
  ImageStyle(id: image, fill: fill(rgba(255, 255, 255, 255)))

proc newFigRenderer*(
    atlasSize: int, backendState: SiwinRenderBackend, pixelScale = 1.0'f32
): FigRenderer[SiwinRenderBackend] =
  FigRenderer[SiwinRenderBackend](
    atlasSize: atlasSize, pixelScale: pixelScale, backendState: backendState
  )

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
    size, fullscreen, title, vsync, msaa, resizable, frameless, transparent
  )

proc newPopupWindow*(
    parent: Window, placement: PopupPlacement, transparent = true, grab = true
): Window =
  figdraw_native_abi.newSiwinPopupWindow(parent, placement, transparent, grab)

proc setupBackend*(renderer: FigRenderer[SiwinRenderBackend], window: Window) =
  let native = figdraw_native_abi.newFigRenderer(
    renderer.atlasSize, renderer.backendState, renderer.pixelScale
  )
  figdraw_native_abi.setupBackend(native, window)
  let autoScale = figdraw_native_abi.configureUiScale(window, "HDI")
  renderer.native = native
  renderer.window = window
  renderer.backendState = default(SiwinRenderBackend)
  renderer.autoScale = autoScale

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

proc `icon=`*(window: Window, image: Image) {.inline.} =
  ## Converts image icons while preserving Siwin's distinct clear-icon call.
  if image.isNil or image.data.len == 0:
    figdraw_native_abi.`icon=`(window, nil)
  else:
    figdraw_native_abi.`icon=`(window, image.toPixelBuffer())

template `vsync=`*(window: Window, value: bool) =
  figdraw_native_abi.`vsync=`(window, value, false)

template firstStep*(window: Window) =
  figdraw_native_abi.firstStep(window, true)

template configureUiScale*(window: Window): bool =
  figdraw_native_abi.configureUiScale(window, "HDI")

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  renderer.window.refreshUiScale(renderer.autoScale)
  figdraw_native_abi.beginFrame(renderer.native)

proc renderFrame*(
    renderer: FigRenderer[SiwinRenderBackend],
    renders: var Renders,
    size: vmath.Vec2,
    clearMain = true,
    clearColor = whiteColor,
) =
  figdraw_native_abi.renderFrame(renderer.native, renders, size, clearMain, clearColor)

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: " & siwinBackendName() & " + " & suffix

proc siwinWindowTitle*(
    renderer: FigRenderer[SiwinRenderBackend],
    window: Window,
    suffix = "Siwin RenderList",
): string =
  discard window
  "figdraw: " & renderer.backendName() & " + " & suffix
