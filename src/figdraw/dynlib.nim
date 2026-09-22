## FigDraw conveniences over the generated native ABI and shared Nim types.

import std/[hashes, macros, options, tables, unicode]
import pkg/bumpy as bumpy
import pkg/chroma as chroma
from pkg/pixie import Image
import pkg/vmath as vmath
import figdraw_native_abi
from figdraw/extras/systemfonttypes import initSystemTypefaceFile, initSystemTypeface
from figdraw/common/fonttypes import nil
from figdraw/common/filltypes import
  FillKind, FillGradientAxis, Linear2, Linear3, sampleColor, centerColorRgba,
  centerColor

when not defined(gcArc):
  {.error: "figdraw/dynlib requires --mm:arc to match the native library".}

export options, tables, bumpy, chroma, vmath
export Image
export
  FillKind, FillGradientAxis, Linear2, Linear3, sampleColor, centerColorRgba,
  centerColor
export figdraw_native_abi except
  placeGlyphs, newSiwinWindow, newSiwinPopupWindow, newFigRenderer, setupBackend,
  drawableDashedRoundedRectBorderOps, drawableDottedRoundedRectBorderOps,
  figDashedRoundedRectBorder, figRoundedRectBorder, figDottedRoundedRectBorder, `[]`,
  Hash, RootObj, MonoTime, MouseButton, ModifierKey, Key, TouchDeviceKind, Edge,
  CursorKind, BuiltinCursor, MouseMoveKind, ScrollDeviceKind, StateBoolChangedEventKind,
  PopupDismissReason, WindowBackdropKind, WindowBackdropMaterial,
  PopupConstraintAdjustment, WindowVisualCapability, SiwinRenderer, SiwinRenderBackend,
  SiwinPresentationTarget, ClipboardContentKind, ClipboardContentChangedEvent,
  Clipboard, PixelBuffer, Touch, Mouse, Keyboard, TouchScreen, Cursor, ImageCursor,
  Screen, Window, WindowEventsHandler, AnyWindowEvent, CloseEvent, RenderEvent,
  TickEvent, ResizeEvent, WindowMoveEvent, MouseMoveEvent, MouseButtonEvent,
  ScrollEvent, ClickEvent, KeyEvent, TextInputEvent, TouchEvent, TouchMoveEvent,
  TouchPressureChangedEvent, StateBoolChangedEvent, PopupEvent, DropEvent,
  WindowBackdropConfig, WindowVisualRegion, PopupPlacement, newFigSiwinApp, closed,
  opened, close, redraw, firstStep, step, makeCurrent, size, `size=`, pos, `pos=`,
  `title=`, visible, `visible=`, focused, fullscreen, `fullscreen=`, maximized,
  `maximized=`, minimized, `minimized=`, resizable, `resizable=`, frameless,
  `frameless=`, transparent, customTitlebar, `customTitlebar=`, supportsCustomTitlebar,
  `vsync=`, separateTouch, `separateTouch=`, canBecomeKeyWindow, `canBecomeKeyWindow=`,
  canBecomeMainWindow, `canBecomeMainWindow=`, minSize, `minSize=`, maxSize, `maxSize=`,
  setTitleRegion, setInputRegion, setBorderWidth, cursor, `cursor=`,
  startInteractiveMove, startInteractiveResize, showWindowMenu, `icon=`, isPopup,
  popupGrab, popupOpen, placement, `placement=`, reposition, parentWindow,
  visualCapabilities, supports, backdrop, trySetBackdrop, clearBackdrop, setBackdrop,
  initWindowBackdrop, clipboard, selectionClipboard, dragndropClipboard, uiScale,
  preservesContentDuringLiveResize, `preservesContentDuringLiveResize=`, text, `text=`,
  files, `files=`, presentationTarget, updatePresentationTarget,
  backendSupportsDedicatedRenderThread, supportsDedicatedRenderThread,
  useDedicatedRenderThread, beginFrame, renderFrame, endFrame, configureUiScale,
  refreshUiScale, presentNow, siwinBackendName, siwinDisplayServerName, getFigFont,
  getTypefaceSource, getTypefaceInfo, typeset, typesetForMeasurement,
  typesetSourceSpans, typesetSourceSpansForMeasurement, generateGlyph,
  generateGlyphImages, hash, getContentHash, findSystemTypeface, findSystemFontFile,
  systemDefaultFontNames, FillKind, FillGradientAxis

proc fontRef*(font: sink FigFont): FontRef {.inline.} =
  newNativeFontRef(font)

proc fontRef*(id: TypefaceId, size: float32): FontRef {.inline.} =
  newNativeFontRef(fontWithSize(id, size))

macro exportSharedValueOperations(operations: typed): untyped =
  ## Export operations on shared value types without unrelated stdlib overloads.
  result = newNimNode(nnkExportStmt)
  for operation in operations:
    let firstParamType = operation.getTypeImpl()[0][1][^2]
    for sharedType in [
      bindSym("TypefaceId"), bindSym("FontId"), bindSym("FontGlyphId"), bindSym("Fill")
    ]:
      if firstParamType.sameType(sharedType):
        result.add operation
        break

exportSharedValueOperations(fonttypes.hash)
exportSharedValueOperations(fonttypes.`==`)

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

proc systemDefaultFontNames*(role = sfrSans): seq[string] {.inline.} =
  figdraw_native_abi.systemDefaultFontNames(role)

proc findSystemTypeface*(
    names: openArray[string], displayServer = detectDisplayServer()
): Option[SystemTypeface] {.inline.} =
  figdraw_native_abi.findSystemTypeface(names, displayServer)

proc findSystemTypeface*(
    names, fontFiles: openArray[string], preserveInputOrder = false
): Option[SystemTypeface] {.inline.} =
  figdraw_native_abi.findSystemTypeface(names, fontFiles, preserveInputOrder)

proc findSystemFontFile*(
    names: openArray[string], displayServer = detectDisplayServer()
): string {.inline.} =
  figdraw_native_abi.findSystemFontFile(names, displayServer)

proc findSystemFontFile*(names, fontFiles: openArray[string]): string {.inline.} =
  figdraw_native_abi.findSystemFontFile(names, fontFiles)

iterator systemTypefaces*(): SystemTypefaceInfo =
  ## Keeps the convenient zero-argument form; the query form is exported directly.
  for info in figdraw_native_abi.systemTypefaces(SystemTypefaceQuery()):
    yield info

proc getFigFont*(id: FontId): FigFont =
  ## Raises in the client when the producer has no registered font.
  if not tryGetFigFont(id, result):
    raise newException(ValueError, "font is not available for id " & $id.int)

proc getTypefaceSource*(id: TypefaceId): TypefaceSource =
  ## Raises in the client when the producer has no registered typeface source.
  if not tryGetTypefaceSource(id, result):
    raise newException(
      ValueError, "typeface source data is not available for id " & $id.int
    )

proc getTypefaceInfo*(id: TypefaceId): TypefaceInfo =
  ## Raises in the client when the producer has no registered typeface metadata.
  if not tryGetTypefaceInfo(id, result):
    raise
      newException(ValueError, "typeface metadata is not available for id " & $id.int)

converter nilToFontRef*(value: typeof(nil)): FontRef =
  discard value
  default(FontRef)

proc `==`*(a, b: FontRef): bool {.inline.} =
  sameFontRef(a, b)

proc `==`*(a, b: OwnerToken): bool {.borrow.}

proc hash*(
    glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0
): hashes.Hash {.inline.} =
  figdraw_native_abi.hash(glyph, lcdFiltering, subpixelVariant)

proc generateGlyph*(
    glyph: GlyphPosition,
    lcdFiltering = false,
    subpixelVariant = 0,
    force = false,
    upload = true,
): Image {.discardable, inline.} =
  figdraw_native_abi.generateGlyph(glyph, lcdFiltering, subpixelVariant, force, upload)

proc generateGlyphImages*(
    arrangement: GlyphArrangement, lcdFiltering = false
) {.inline.} =
  figdraw_native_abi.generateGlyphImages(arrangement, lcdFiltering)

proc getContentHash*[T: FontStyle | FigFont](
    size: Vec2,
    spans: openArray[(T, string)],
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = false,
): hashes.Hash {.inline.} =
  figdraw_native_abi.getContentHash(size, spans, hAlign, vAlign, minContent, wrap)

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
  ImageRef* = NativeImageRef

  CornerRadii2D*[T] = object
    x*, y*: array[DirectionCorners, T]

converter nilToImageRef*(value: typeof(nil)): ImageRef =
  discard value
  default(ImageRef)

func id*(image: ImageRef): ImageId {.inline.} =
  ## The image ID owned by this handle.
  image.imageId()

converter toRuneSequence*(runes: figdraw_native_abi.Utf8Runes): seq[unicode.Rune] =
  runes.toRunes()

converter toUtf8Runes*(runes: seq[unicode.Rune]): figdraw_native_abi.Utf8Runes =
  figdraw_native_abi.initUtf8Runes(runes)

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

proc typesetSourceSpans*(
    box: bumpy.Rect,
    source: Utf8Runes,
    spans: openArray[TextSourceSpan],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  figdraw_native_abi.typesetSourceSpans(
    box, source, spans, hAlign, vAlign, minContent, wrap
  )

proc typesetSourceSpansForMeasurement*(
    box: bumpy.Rect,
    source: Utf8Runes,
    spans: openArray[TextSourceSpan],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  figdraw_native_abi.typesetSourceSpansForMeasurement(
    box, source, spans, hAlign, vAlign, minContent, wrap
  )

proc typeset*[T: FigFont | FontRef](
    box: bumpy.Rect,
    font: T,
    text: string,
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  typeset(
    box,
    [(figdraw_native_abi.fs(font, fill(rgba(0, 0, 0, 255))), text)],
    hAlign,
    vAlign,
    minContent,
    wrap,
  )

proc typeset*[T: FigFont | FontRef](
    box: bumpy.Rect,
    spans: openArray[(T, string)],
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  var styled = newSeqOfCap[(FontStyle, string)](spans.len)
  for (font, text) in spans:
    styled.add((figdraw_native_abi.fs(font, fill(rgba(0, 0, 0, 255))), text))
  typeset(box, styled, hAlign, vAlign, minContent, wrap)

proc typesetForMeasurement*[T: FigFont | FontRef](
    box: bumpy.Rect,
    font: T,
    text: string,
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
): GlyphArrangement {.inline.} =
  typesetForMeasurement(
    box,
    [(figdraw_native_abi.fs(font, fill(rgba(0, 0, 0, 255))), text)],
    hAlign,
    vAlign,
    minContent,
    wrap,
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

proc fs*(font: FontRef): FontStyle {.inline.} =
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

proc placeGlyphs*[T: FigFont | FontRef](
    font: T, glyphs: openArray[(unicode.Rune, vmath.Vec2)], origin = GlyphTopLeft
): GlyphArrangement {.inline.} =
  placeGlyphs(fs(font), glyphs, origin)

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
  newNativeImageRef(loadFigImage(filePath))

proc imageRef*(id: ImageId): ImageRef {.inline.} =
  newNativeImageRef(id)

proc imageRef*(id: ImageId, image: sink Image): ImageRef =
  figdraw_native_abi.loadImage(id, ensureMove image)
  imageRef(id)

proc loadImage*[T](id: ImageId, image: T) {.inline.} =
  figdraw_native_abi.loadImage(id, image.toImage())

proc replaceImage*[T](id: ImageId, image: T) {.inline.} =
  figdraw_native_abi.replaceImage(id, image.toImage())

proc imageStyle*(
    id: ImageId, imageFill: Fill = fill(rgba(255, 255, 255, 255))
): ImageStyle =
  ImageStyle(id: id, fill: imageFill)

proc imageStyle*(
    image: ImageRef, imageFill: Fill = fill(rgba(255, 255, 255, 255))
): ImageStyle =
  imageStyle(image.id, imageFill)

proc zlevel*(cursor: RenderCursor): ZLevel {.inline.} =
  nativeRenderCursorZLevel(cursor)

proc index*(cursor: RenderCursor): FigIdx {.inline.} =
  nativeRenderCursorIndex(cursor)

proc drawableDashedRoundedRectBorderOps*(
    box: bumpy.Rect,
    corners: array[DirectionCorners, uint16],
    dashLength, gapLength: float32,
    offset = 0.0'f32,
): seq[DrawableOp] =
  figdraw_native_abi.drawableDashedRoundedRectBorderOps(
    box, corners, dashLength, gapLength, offset
  )

proc drawableDottedRoundedRectBorderOps*(
    box: bumpy.Rect,
    corners: array[DirectionCorners, uint16],
    dotRadius, gapLength: float32,
    offset = 0.0'f32,
): seq[DrawableOp] =
  figdraw_native_abi.drawableDottedRoundedRectBorderOps(
    box, corners, dotRadius, gapLength, offset
  )

proc figDashedRoundedRectBorder*(
    box: bumpy.Rect,
    corners: CornerRadii,
    fill: Fill,
    weight, dashLength, gapLength: float32,
    offset = 0.0'f32,
    cap = scButt,
    zlevel = 0.ZLevel,
): Fig =
  figdraw_native_abi.figDashedRoundedRectBorder(
    box, corners, fill, weight, dashLength, gapLength, offset, cap, zlevel
  )

proc figRoundedRectBorder*(
    box: bumpy.Rect,
    corners: CornerRadii,
    fill: Fill,
    weight: float32,
    cap = scButt,
    zlevel = 0.ZLevel,
): Fig =
  figdraw_native_abi.figRoundedRectBorder(box, corners, fill, weight, cap, zlevel)

proc figDottedRoundedRectBorder*(
    box: bumpy.Rect,
    corners: CornerRadii,
    fill: Fill,
    weight, gapLength: float32,
    offset = 0.0'f32,
    zlevel = 0.ZLevel,
): Fig =
  figdraw_native_abi.figDottedRoundedRectBorder(
    box, corners, fill, weight, gapLength, offset, zlevel
  )
