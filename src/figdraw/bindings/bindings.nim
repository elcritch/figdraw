import genny
import std/tables
import std/hashes
import vmath
import std/os
import figdraw/commons
import figdraw/fignodes as fdn
import figdraw/figrender as fgr
import figdraw/common/fonttypes as fnt
from figdraw/fignodes import Renders
from figdraw/common/fonttypes import FontCase
from figdraw/common/shared import FigDrawError
import figdraw/common/fontutils as fut
when not defined(emscripten):
  import figdraw/utils/glutils

const ExportSiwinShim* {.booldefine: "figdraw.bindings.siwinshim".} = true
const GeneratedDir = currentSourcePath().parentDir / "generated"

when ExportSiwinShim and not defined(emscripten):
  import figdraw/windowing/siwinshim as siwinshim

var lastError: ref FigDrawError

proc raiseFigDrawError(e: ref Exception) {.raises: [FigDrawError].} =
  if e.isNil:
    raise newException(FigDrawError, "Unknown FigDraw binding error")
  raise newException(FigDrawError, e.msg, e)

proc takeError(): string =
  if lastError.isNil:
    return ""
  result = lastError.msg
  lastError = nil

proc checkError(): bool =
  result = lastError != nil

template returnIfNil(value: untyped) =
  if value.isNil:
    return

template withFigDrawError(body: untyped) =
  try:
    body
  except Exception as e:
    raiseFigDrawError(e)

type
  CornerRadii* = object
    topLeft*, topRight*, bottomLeft*, bottomRight*: uint16

  ScreenBox* = object
    x*, y*, w*, h*: float32

  WindowSize* = object
    w*, h*: int32

  FigRef* = ref object
    inner: fdn.Fig

  FigRendererRef* = ref object
    inner: fgr.FigRenderer[fgr.NoRendererBackendState]

  TypefaceRef* = ref object
    id: fnt.TypefaceId

  FigFontRef* = ref object
    inner: fnt.FigFont

  GlyphLayoutRef* = ref object
    inner: fnt.GlyphArrangement

when ExportSiwinShim and not defined(emscripten):
  type FigSiwinAppRef* = ref object
    window: siwinshim.Window
    renderer: fgr.FigRenderer[siwinshim.SiwinRenderBackend]
    autoScale: bool

proc newFig(): FigRef =
  FigRef(inner: fdn.Fig(kind: fdn.nkFrame))

proc initRgba(r, g, b, a: uint8): ColorRGBA =
  ColorRGBA(r: r, g: g, b: b, a: a)

proc colorRgba(r, g, b, a: uint8): ColorRGBA =
  initRgba(r, g, b, a)

proc toChroma(color: ColorRGBA): chroma.ColorRGBA =
  rgba(color.r, color.g, color.b, color.a)

proc cornerRadii(topLeft, topRight, bottomLeft, bottomRight: float32): CornerRadii =
  CornerRadii(
    topLeft: topLeft.uint16,
    topRight: topRight.uint16,
    bottomLeft: bottomLeft.uint16,
    bottomRight: bottomRight.uint16,
  )

func toFigKind(kind: int8): fdn.FigKind =
  let raw = kind.int
  if raw < ord(low(fdn.FigKind)) or raw > ord(high(fdn.FigKind)):
    fdn.nkFrame
  else:
    fdn.FigKind(raw)

func toImageId(imageId: int64): ImageId =
  cast[ImageId](Hash(imageId))

func toInt64(imageId: ImageId): int64 =
  cast[Hash](imageId).int64

func defaultFill(): Fill =
  fill(rgba(255, 255, 255, 255))

func defaultImageStyle(imageId: int64): ImageStyle =
  ImageStyle(id: imageId.toImageId(), fill: defaultFill())

func defaultMsdfImageStyle(imageId: int64): MsdfImageStyle =
  MsdfImageStyle(id: imageId.toImageId(), fill: defaultFill())

func fillKindValue(value: Fill): FillKind =
  value.kind

func fillColorValue(value: Fill): ColorRGBA =
  case value.kind
  of flColor:
    value.color
  of flLinear2, flLinear3:
    value.centerColorRgba()

func fillLinear2StartValue(value: Fill): ColorRGBA =
  if value.kind == flLinear2:
    value.lin2.start
  else:
    fillColorValue(value)

func fillLinear2StopValue(value: Fill): ColorRGBA =
  if value.kind == flLinear2:
    value.lin2.stop
  else:
    fillColorValue(value)

func fillLinear2AxisValue(value: Fill): FillGradientAxis =
  if value.kind == flLinear2: value.lin2.axis else: fgaX

func fillLinear3StartValue(value: Fill): ColorRGBA =
  if value.kind == flLinear3:
    value.lin3.start
  else:
    fillColorValue(value)

func fillLinear3MidValue(value: Fill): ColorRGBA =
  if value.kind == flLinear3:
    value.lin3.mid
  else:
    fillColorValue(value)

func fillLinear3StopValue(value: Fill): ColorRGBA =
  if value.kind == flLinear3:
    value.lin3.stop
  else:
    fillColorValue(value)

func fillLinear3AxisValue(value: Fill): FillGradientAxis =
  if value.kind == flLinear3: value.lin3.axis else: fgaX

func fillLinear3MidPosValue(value: Fill): uint8 =
  if value.kind == flLinear3: value.lin3.midPos else: 128'u8

func matrixComponent(matrix: Mat4, row, col: int8): float32 =
  if row < 0'i8 or row > 3'i8 or col < 0'i8 or col > 3'i8:
    return 0'f32
  matrix[row.int, col.int]

proc newRectangleFig(x, y, w, h: float32): FigRef =
  FigRef(
    inner:
      fdn.Fig(kind: fdn.nkRectangle, screenBox: rect(x, y, w, h), fill: defaultFill())
  )

proc newTextFig(x, y, w, h: float32): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkText,
      screenBox: rect(x, y, w, h),
      fill: defaultFill(),
      textLayout: GlyphArrangement(),
    )
  )

proc newDrawableFig(x, y, w, h: float32): FigRef =
  FigRef(
    inner:
      fdn.Fig(kind: fdn.nkDrawable, screenBox: rect(x, y, w, h), fill: defaultFill())
  )

proc newImageFig(x, y, w, h: float32, imageId: int64): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkImage,
      screenBox: rect(x, y, w, h),
      fill: defaultFill(),
      image: defaultImageStyle(imageId),
    )
  )

proc newMsdfImageFig(
    x, y, w, h: float32, imageId: int64, pxRange, sdThreshold, strokeWeight: float32
): FigRef =
  var style = defaultMsdfImageStyle(imageId)
  style.pxRange = pxRange
  style.sdThreshold = sdThreshold
  style.strokeWeight = strokeWeight
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkMsdfImage,
      screenBox: rect(x, y, w, h),
      fill: defaultFill(),
      msdfImage: style,
    )
  )

proc newMtsdfImageFig(
    x, y, w, h: float32, imageId: int64, pxRange, sdThreshold, strokeWeight: float32
): FigRef =
  var style = defaultMsdfImageStyle(imageId)
  style.pxRange = pxRange
  style.sdThreshold = sdThreshold
  style.strokeWeight = strokeWeight
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkMtsdfImage,
      screenBox: rect(x, y, w, h),
      fill: defaultFill(),
      mtsdfImage: style,
    )
  )

proc newBackdropBlurFig(x, y, w, h, blur: float32): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkBackdropBlur,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(0, 0, 0, 0)),
      backdropBlur: BackdropBlurStyle(blur: blur),
    )
  )

proc newTransformFig(x, y, w, h: float32, tx, ty: float32): FigRef =
  FigRef(
    inner: fdn.Fig(
      kind: fdn.nkTransform,
      screenBox: rect(x, y, w, h),
      fill: defaultFill(),
      transform: TransformStyle(translation: vec2(tx, ty), useMatrix: false),
    )
  )

proc loadTypefaceBinding(name: string): TypefaceRef {.raises: [FigDrawError].} =
  withFigDrawError:
    let fontId = fut.loadTypeface(name)
    result = TypefaceRef(id: cast[fnt.TypefaceId](fontId))

proc newFigFontBinding(typeface: TypefaceRef, size: float32): FigFontRef =
  if typeface.isNil:
    return nil
  FigFontRef(inner: fnt.FigFont(typefaceId: typeface.id, size: size))

proc setFigFontLineHeightBinding(font: FigFontRef, lineHeight: float32) =
  returnIfNil font
  font.inner.lineHeight = lineHeight

proc setFigFontCaseBinding(font: FigFontRef, fontCase: FontCase) =
  returnIfNil font
  font.inner.fontCase = fontCase

proc typesetTextBinding(
    width, height: float32,
    font: FigFontRef,
    text: string,
    hAlign: int8 = 0,
    vAlign: int8 = 0,
    minContent = false,
    wrap = false,
): GlyphLayoutRef {.raises: [FigDrawError].} =
  if font.isNil:
    return nil
  var h = fnt.FontHorizontal.Left
  case hAlign
  of 1'i8:
    h = fnt.FontHorizontal.Center
  of 2'i8:
    h = fnt.FontHorizontal.Right
  else:
    discard

  var v = fnt.FontVertical.Top
  case vAlign
  of 1'i8:
    v = fnt.FontVertical.Middle
  of 2'i8:
    v = fnt.FontVertical.Bottom
  else:
    discard

  try:
    let layout = fut.typeset(
      box = rect(0'f32, 0'f32, width, height),
      uiSpans = @[(font.inner, text)],
      hAlign = h,
      vAlign = v,
      minContent = minContent,
      wrap = wrap,
    )
    result = GlyphLayoutRef(inner: layout)
  except Exception as e:
    raiseFigDrawError(e)

proc figWithKind(src: fdn.Fig, kind: fdn.FigKind): fdn.Fig {.raises: [].}

proc setFigTextLayoutBinding(
    fig: FigRef, layout: GlyphLayoutRef
) {.raises: [FigDrawError].} =
  if fig.isNil or layout.isNil:
    return
  withFigDrawError:
    if fig.inner.kind != fdn.nkText:
      fig.inner = figWithKind(fig.inner, fdn.nkText)
    fig.inner.textLayout = layout.inner

proc textLayoutWidthBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.w

proc textLayoutHeightBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.h

proc copy(fig: FigRef): FigRef =
  if fig.isNil:
    return nil
  FigRef(inner: fig.inner)

proc figWithKind(src: fdn.Fig, kind: fdn.FigKind): fdn.Fig {.raises: [].} =
  result = fdn.Fig(kind: kind)
  result.zlevel = src.zlevel
  result.parent = src.parent
  result.flags = src.flags
  result.childCount = src.childCount
  result.screenBox = src.screenBox
  result.rotation = src.rotation
  result.fill = src.fill
  result.corners = src.corners

proc setRectangleKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)

proc setTextKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkText:
    fig.inner = figWithKind(fig.inner, fdn.nkText)

proc setDrawableKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkDrawable:
    fig.inner = figWithKind(fig.inner, fdn.nkDrawable)

proc setImageKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkImage:
    fig.inner = figWithKind(fig.inner, fdn.nkImage)
    fig.inner.image = defaultImageStyle(0)

proc setMsdfImageKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkMsdfImage:
    fig.inner = figWithKind(fig.inner, fdn.nkMsdfImage)
    fig.inner.msdfImage = defaultMsdfImageStyle(0)

proc setMtsdfImageKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkMtsdfImage:
    fig.inner = figWithKind(fig.inner, fdn.nkMtsdfImage)
    fig.inner.mtsdfImage = defaultMsdfImageStyle(0)

proc setBackdropBlurKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkBackdropBlur:
    fig.inner = figWithKind(fig.inner, fdn.nkBackdropBlur)

proc setTransformKind(fig: FigRef) =
  returnIfNil fig
  if fig.inner.kind != fdn.nkTransform:
    fig.inner = figWithKind(fig.inner, fdn.nkTransform)

proc kind(fig: FigRef): int8 =
  if fig.isNil:
    return fdn.nkFrame.int8
  fig.inner.kind.int8

proc setKind(fig: FigRef, kind: int8) =
  returnIfNil fig
  fig.inner = figWithKind(fig.inner, kind.toFigKind())

proc zLevel(fig: FigRef): int8 =
  if fig.isNil:
    return 0'i8
  fig.inner.zlevel.int8

proc setZLevel(fig: FigRef, zLevel: int8) =
  returnIfNil fig
  fig.inner.zlevel = fdn.ZLevel(zLevel)

proc childCount(fig: FigRef): int16 =
  if fig.isNil:
    return 0'i16
  fig.inner.childCount

proc parentIndex(fig: FigRef): int16 =
  if fig.isNil:
    return -1'i16
  fig.inner.parent.int16

proc hasFlag(fig: FigRef, flag: FigFlags): bool =
  if fig.isNil:
    return false
  flag in fig.inner.flags

proc setFlag(fig: FigRef, flag: FigFlags, enabled: bool) =
  returnIfNil fig
  if enabled:
    fig.inner.flags.incl flag
  else:
    fig.inner.flags.excl flag

proc clearFlags(fig: FigRef) =
  returnIfNil fig
  fig.inner.flags = {}

proc getScreenBox(fig: FigRef): ScreenBox =
  if fig.isNil:
    return ScreenBox()
  ScreenBox(
    x: fig.inner.screenBox.x,
    y: fig.inner.screenBox.y,
    w: fig.inner.screenBox.w,
    h: fig.inner.screenBox.h,
  )

proc setScreenBox(fig: FigRef, x, y, w, h: float32) =
  returnIfNil fig
  fig.inner.screenBox = rect(x, y, w, h)

proc setFillColor(fig: FigRef, r, g, b, a: uint8) =
  returnIfNil fig
  fig.inner.fill = fill(rgba(r, g, b, a))

proc setFillColorRgba(fig: FigRef, color: ColorRGBA) =
  returnIfNil fig
  fig.inner.fill = fill(color.toChroma())

proc setFillLinear2(
    fig: FigRef, startColor, endColor: ColorRGBA, axis: FillGradientAxis
) =
  returnIfNil fig
  fig.inner.fill = linear(startColor.toChroma(), endColor.toChroma(), axis = axis)

proc setFillLinear3(
    fig: FigRef,
    startColor, midColor, endColor: ColorRGBA,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  returnIfNil fig
  fig.inner.fill = linear(
    startColor.toChroma(),
    midColor.toChroma(),
    endColor.toChroma(),
    axis = axis,
    midPos = midPos,
  )

proc fillKind(fig: FigRef): FillKind =
  if fig.isNil:
    return flColor
  fig.inner.fill.fillKindValue()

proc fillColor(fig: FigRef): ColorRGBA =
  if fig.isNil:
    return initRgba(0, 0, 0, 0)
  fig.inner.fill.fillColorValue()

proc fillLinear2Start(fig: FigRef): ColorRGBA =
  if fig.isNil:
    return initRgba(0, 0, 0, 0)
  fig.inner.fill.fillLinear2StartValue()

proc fillLinear2Stop(fig: FigRef): ColorRGBA =
  if fig.isNil:
    return initRgba(0, 0, 0, 0)
  fig.inner.fill.fillLinear2StopValue()

proc fillLinear2Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil:
    return fgaX
  fig.inner.fill.fillLinear2AxisValue()

proc fillLinear3Start(fig: FigRef): ColorRGBA =
  if fig.isNil:
    return initRgba(0, 0, 0, 0)
  fig.inner.fill.fillLinear3StartValue()

proc fillLinear3Mid(fig: FigRef): ColorRGBA =
  if fig.isNil:
    return initRgba(0, 0, 0, 0)
  fig.inner.fill.fillLinear3MidValue()

proc fillLinear3Stop(fig: FigRef): ColorRGBA =
  if fig.isNil:
    return initRgba(0, 0, 0, 0)
  fig.inner.fill.fillLinear3StopValue()

proc fillLinear3Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil:
    return fgaX
  fig.inner.fill.fillLinear3AxisValue()

proc fillLinear3MidPos(fig: FigRef): uint8 =
  if fig.isNil:
    return 128'u8
  fig.inner.fill.fillLinear3MidPosValue()

proc rotation(fig: FigRef): float32 =
  if fig.isNil:
    return 0'f32
  fig.inner.rotation

proc setRotation(fig: FigRef, rotation: float32) =
  returnIfNil fig
  fig.inner.rotation = rotation

proc getCorners(fig: FigRef): CornerRadii =
  if fig.isNil:
    return CornerRadii()
  CornerRadii(
    topLeft: fig.inner.corners[dcTopLeft],
    topRight: fig.inner.corners[dcTopRight],
    bottomLeft: fig.inner.corners[dcBottomLeft],
    bottomRight: fig.inner.corners[dcBottomRight],
  )

proc setCorners(fig: FigRef, radii: CornerRadii) =
  returnIfNil fig
  fig.inner.corners =
    [radii.topLeft, radii.topRight, radii.bottomLeft, radii.bottomRight]

proc setStroke(fig: FigRef, weight: float32, color: ColorRGBA) =
  returnIfNil fig
  fig.setRectangleKind()
  fig.inner.stroke = RenderStroke(weight: weight, fill: fill(color.toChroma()))

proc strokeWeight(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle:
    return 0'f32
  fig.inner.stroke.weight

proc strokeColor(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle:
    return initRgba(0, 0, 0, 0)
  fig.inner.stroke.fill.fillColorValue()

proc clearShadows(fig: FigRef) =
  returnIfNil fig
  fig.setRectangleKind()
  fig.inner.shadows = [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()]

proc setShadow(
    fig: FigRef,
    shadowIndex: int8,
    style: ShadowStyle,
    blur, spread, x, y: float32,
    color: ColorRGBA,
) =
  returnIfNil fig
  fig.setRectangleKind()
  if shadowIndex < 0'i8 or shadowIndex >= ShadowCount.int8:
    return

  fig.inner.shadows[shadowIndex.int] = RenderShadow(
    style: style, blur: blur, spread: spread, x: x, y: y, fill: fill(color.toChroma())
  )

proc validShadowIndex(shadowIndex: int8): bool =
  shadowIndex >= 0'i8 and shadowIndex < ShadowCount.int8

proc shadowStyle(fig: FigRef, shadowIndex: int8): ShadowStyle =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle or not validShadowIndex(shadowIndex):
    return NoShadow
  fig.inner.shadows[shadowIndex.int].style

proc shadowBlur(fig: FigRef, shadowIndex: int8): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle or not validShadowIndex(shadowIndex):
    return 0'f32
  fig.inner.shadows[shadowIndex.int].blur

proc shadowSpread(fig: FigRef, shadowIndex: int8): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle or not validShadowIndex(shadowIndex):
    return 0'f32
  fig.inner.shadows[shadowIndex.int].spread

proc shadowX(fig: FigRef, shadowIndex: int8): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle or not validShadowIndex(shadowIndex):
    return 0'f32
  fig.inner.shadows[shadowIndex.int].x

proc shadowY(fig: FigRef, shadowIndex: int8): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle or not validShadowIndex(shadowIndex):
    return 0'f32
  fig.inner.shadows[shadowIndex.int].y

proc shadowColor(fig: FigRef, shadowIndex: int8): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkRectangle or not validShadowIndex(shadowIndex):
    return initRgba(0, 0, 0, 0)
  fig.inner.shadows[shadowIndex.int].fill.fillColorValue()

proc setSelectionRange(fig: FigRef, first, last: int16) =
  returnIfNil fig
  fig.setTextKind()
  fig.inner.selectionRange = first .. last

proc selectionFirst(fig: FigRef): int16 =
  if fig.isNil or fig.inner.kind != fdn.nkText:
    return 0'i16
  fig.inner.selectionRange.a.int16

proc selectionLast(fig: FigRef): int16 =
  if fig.isNil or fig.inner.kind != fdn.nkText:
    return -1'i16
  fig.inner.selectionRange.b.int16

proc drawablePointOp(fig: FigRef, x, y: float32): fdn.DrawableOp =
  fdn.drawableRect(rect(x, y, fig.inner.screenBox.w, fig.inner.screenBox.h))

proc clearDrawablePoints(fig: FigRef) =
  returnIfNil fig
  fig.setDrawableKind()
  fig.inner.drawOps.setLen(0)

proc addDrawablePoint(fig: FigRef, x, y: float32) =
  returnIfNil fig
  fig.setDrawableKind()
  fig.inner.drawOps.add fig.drawablePointOp(x, y)

proc drawablePointCount(fig: FigRef): int =
  if fig.isNil or fig.inner.kind != fdn.nkDrawable:
    return 0
  fig.inner.drawOps.len

proc drawablePointX(fig: FigRef, index: int): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkDrawable:
    return 0'f32
  if index < 0 or index >= fig.inner.drawOps.len:
    return 0'f32
  let op = fig.inner.drawOps[index]
  case op.kind
  of fdn.dkLine:
    op.a.x
  of fdn.dkCircle:
    op.center.x
  of fdn.dkRectangle:
    op.box.x
  of fdn.dkBezier:
    if op.controls.len > 0:
      op.controls[0].x
    else:
      0'f32

proc drawablePointY(fig: FigRef, index: int): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkDrawable:
    return 0'f32
  if index < 0 or index >= fig.inner.drawOps.len:
    return 0'f32
  let op = fig.inner.drawOps[index]
  case op.kind
  of fdn.dkLine:
    op.a.y
  of fdn.dkCircle:
    op.center.y
  of fdn.dkRectangle:
    op.box.y
  of fdn.dkBezier:
    if op.controls.len > 0:
      op.controls[0].y
    else:
      0'f32

proc setDrawablePoint(fig: FigRef, index: int, x, y: float32) =
  returnIfNil fig
  fig.setDrawableKind()
  if index < 0:
    return
  if index >= fig.inner.drawOps.len:
    fig.inner.drawOps.setLen(index + 1)
  fig.inner.drawOps[index] = fig.drawablePointOp(x, y)

proc imageId(fig: FigRef): int64 =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return 0'i64
  fig.inner.image.id.toInt64()

proc setImageId(fig: FigRef, imageId: int64) =
  returnIfNil fig
  fig.setImageKind()
  fig.inner.image.id = imageId.toImageId()

proc setImageFillColorRgba(fig: FigRef, color: ColorRGBA) =
  returnIfNil fig
  fig.setImageKind()
  fig.inner.image.fill = fill(color.toChroma())

proc setImageFillLinear2(
    fig: FigRef, startColor, endColor: ColorRGBA, axis: FillGradientAxis
) =
  returnIfNil fig
  fig.setImageKind()
  fig.inner.image.fill = linear(startColor.toChroma(), endColor.toChroma(), axis)

proc setImageFillLinear3(
    fig: FigRef,
    startColor, midColor, endColor: ColorRGBA,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  returnIfNil fig
  fig.setImageKind()
  fig.inner.image.fill = linear(
    startColor.toChroma(), midColor.toChroma(), endColor.toChroma(), axis, midPos
  )

proc imageFillKind(fig: FigRef): FillKind =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return flColor
  fig.inner.image.fill.fillKindValue()

proc imageFillColor(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.image.fill.fillColorValue()

proc imageFillLinear2Start(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.image.fill.fillLinear2StartValue()

proc imageFillLinear2Stop(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.image.fill.fillLinear2StopValue()

proc imageFillLinear2Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return fgaX
  fig.inner.image.fill.fillLinear2AxisValue()

proc imageFillLinear3Start(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.image.fill.fillLinear3StartValue()

proc imageFillLinear3Mid(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.image.fill.fillLinear3MidValue()

proc imageFillLinear3Stop(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.image.fill.fillLinear3StopValue()

proc imageFillLinear3Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return fgaX
  fig.inner.image.fill.fillLinear3AxisValue()

proc imageFillLinear3MidPos(fig: FigRef): uint8 =
  if fig.isNil or fig.inner.kind != fdn.nkImage:
    return 128'u8
  fig.inner.image.fill.fillLinear3MidPosValue()

proc setMsdfImage(
    fig: FigRef, imageId: int64, pxRange, sdThreshold, strokeWeight: float32
) =
  returnIfNil fig
  fig.setMsdfImageKind()
  fig.inner.msdfImage.id = imageId.toImageId()
  fig.inner.msdfImage.pxRange = pxRange
  fig.inner.msdfImage.sdThreshold = sdThreshold
  fig.inner.msdfImage.strokeWeight = strokeWeight

proc msdfImageId(fig: FigRef): int64 =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return 0'i64
  fig.inner.msdfImage.id.toInt64()

proc msdfImagePxRange(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return 0'f32
  fig.inner.msdfImage.pxRange

proc msdfImageSdThreshold(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return 0'f32
  fig.inner.msdfImage.sdThreshold

proc msdfImageStrokeWeight(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return 0'f32
  fig.inner.msdfImage.strokeWeight

proc setMsdfImageFillColorRgba(fig: FigRef, color: ColorRGBA) =
  returnIfNil fig
  fig.setMsdfImageKind()
  fig.inner.msdfImage.fill = fill(color.toChroma())

proc setMsdfImageFillLinear2(
    fig: FigRef, startColor, endColor: ColorRGBA, axis: FillGradientAxis
) =
  returnIfNil fig
  fig.setMsdfImageKind()
  fig.inner.msdfImage.fill = linear(startColor.toChroma(), endColor.toChroma(), axis)

proc setMsdfImageFillLinear3(
    fig: FigRef,
    startColor, midColor, endColor: ColorRGBA,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  returnIfNil fig
  fig.setMsdfImageKind()
  fig.inner.msdfImage.fill = linear(
    startColor.toChroma(), midColor.toChroma(), endColor.toChroma(), axis, midPos
  )

proc msdfImageFillKind(fig: FigRef): FillKind =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return flColor
  fig.inner.msdfImage.fill.fillKindValue()

proc msdfImageFillColor(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.msdfImage.fill.fillColorValue()

proc msdfImageFillLinear2Start(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.msdfImage.fill.fillLinear2StartValue()

proc msdfImageFillLinear2Stop(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.msdfImage.fill.fillLinear2StopValue()

proc msdfImageFillLinear2Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return fgaX
  fig.inner.msdfImage.fill.fillLinear2AxisValue()

proc msdfImageFillLinear3Start(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.msdfImage.fill.fillLinear3StartValue()

proc msdfImageFillLinear3Mid(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.msdfImage.fill.fillLinear3MidValue()

proc msdfImageFillLinear3Stop(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.msdfImage.fill.fillLinear3StopValue()

proc msdfImageFillLinear3Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return fgaX
  fig.inner.msdfImage.fill.fillLinear3AxisValue()

proc msdfImageFillLinear3MidPos(fig: FigRef): uint8 =
  if fig.isNil or fig.inner.kind != fdn.nkMsdfImage:
    return 128'u8
  fig.inner.msdfImage.fill.fillLinear3MidPosValue()

proc setMtsdfImage(
    fig: FigRef, imageId: int64, pxRange, sdThreshold, strokeWeight: float32
) =
  returnIfNil fig
  fig.setMtsdfImageKind()
  fig.inner.mtsdfImage.id = imageId.toImageId()
  fig.inner.mtsdfImage.pxRange = pxRange
  fig.inner.mtsdfImage.sdThreshold = sdThreshold
  fig.inner.mtsdfImage.strokeWeight = strokeWeight

proc mtsdfImageId(fig: FigRef): int64 =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return 0'i64
  fig.inner.mtsdfImage.id.toInt64()

proc mtsdfImagePxRange(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return 0'f32
  fig.inner.mtsdfImage.pxRange

proc mtsdfImageSdThreshold(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return 0'f32
  fig.inner.mtsdfImage.sdThreshold

proc mtsdfImageStrokeWeight(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return 0'f32
  fig.inner.mtsdfImage.strokeWeight

proc setMtsdfImageFillColorRgba(fig: FigRef, color: ColorRGBA) =
  returnIfNil fig
  fig.setMtsdfImageKind()
  fig.inner.mtsdfImage.fill = fill(color.toChroma())

proc setMtsdfImageFillLinear2(
    fig: FigRef, startColor, endColor: ColorRGBA, axis: FillGradientAxis
) =
  returnIfNil fig
  fig.setMtsdfImageKind()
  fig.inner.mtsdfImage.fill = linear(startColor.toChroma(), endColor.toChroma(), axis)

proc setMtsdfImageFillLinear3(
    fig: FigRef,
    startColor, midColor, endColor: ColorRGBA,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  returnIfNil fig
  fig.setMtsdfImageKind()
  fig.inner.mtsdfImage.fill = linear(
    startColor.toChroma(), midColor.toChroma(), endColor.toChroma(), axis, midPos
  )

proc mtsdfImageFillKind(fig: FigRef): FillKind =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return flColor
  fig.inner.mtsdfImage.fill.fillKindValue()

proc mtsdfImageFillColor(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.mtsdfImage.fill.fillColorValue()

proc mtsdfImageFillLinear2Start(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.mtsdfImage.fill.fillLinear2StartValue()

proc mtsdfImageFillLinear2Stop(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.mtsdfImage.fill.fillLinear2StopValue()

proc mtsdfImageFillLinear2Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return fgaX
  fig.inner.mtsdfImage.fill.fillLinear2AxisValue()

proc mtsdfImageFillLinear3Start(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.mtsdfImage.fill.fillLinear3StartValue()

proc mtsdfImageFillLinear3Mid(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.mtsdfImage.fill.fillLinear3MidValue()

proc mtsdfImageFillLinear3Stop(fig: FigRef): ColorRGBA =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return initRgba(0, 0, 0, 0)
  fig.inner.mtsdfImage.fill.fillLinear3StopValue()

proc mtsdfImageFillLinear3Axis(fig: FigRef): FillGradientAxis =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return fgaX
  fig.inner.mtsdfImage.fill.fillLinear3AxisValue()

proc mtsdfImageFillLinear3MidPos(fig: FigRef): uint8 =
  if fig.isNil or fig.inner.kind != fdn.nkMtsdfImage:
    return 128'u8
  fig.inner.mtsdfImage.fill.fillLinear3MidPosValue()

proc setBackdropBlur(fig: FigRef, blur: float32) =
  returnIfNil fig
  fig.setBackdropBlurKind()
  fig.inner.backdropBlur.blur = blur

proc backdropBlur(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkBackdropBlur:
    return 0'f32
  fig.inner.backdropBlur.blur

proc setTransformTranslation(fig: FigRef, x, y: float32) =
  returnIfNil fig
  fig.setTransformKind()
  fig.inner.transform.translation = vec2(x, y)

proc transformTranslationX(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkTransform:
    return 0'f32
  fig.inner.transform.translation.x

proc transformTranslationY(fig: FigRef): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkTransform:
    return 0'f32
  fig.inner.transform.translation.y

proc transformUseMatrix(fig: FigRef): bool =
  if fig.isNil or fig.inner.kind != fdn.nkTransform:
    return false
  fig.inner.transform.useMatrix

proc setTransformUseMatrix(fig: FigRef, useMatrix: bool) =
  returnIfNil fig
  fig.setTransformKind()
  fig.inner.transform.useMatrix = useMatrix

proc setTransformMatrix(
    fig: FigRef,
    m00, m01, m02, m03: float32,
    m10, m11, m12, m13: float32,
    m20, m21, m22, m23: float32,
    m30, m31, m32, m33: float32,
) =
  returnIfNil fig
  fig.setTransformKind()
  fig.inner.transform.matrix =
    mat4(m00, m01, m02, m03, m10, m11, m12, m13, m20, m21, m22, m23, m30, m31, m32, m33)
  fig.inner.transform.useMatrix = true

proc transformMatrixValue(fig: FigRef, row, col: int8): float32 =
  if fig.isNil or fig.inner.kind != fdn.nkTransform:
    return 0'f32
  fig.inner.transform.matrix.matrixComponent(row, col)

proc newRenders(): Renders =
  Renders(layers: initOrderedTable[fdn.ZLevel, fdn.RenderList]())

proc startOpenGLForBindings() =
  when not defined(emscripten):
    startOpenGL(openglVersion)

proc newFigRendererBinding*(
    atlasSize: int, pixelScale: float32
): FigRendererRef {.raises: [FigDrawError].} =
  withFigDrawError:
    startOpenGLForBindings()
    result = FigRendererRef(inner: fgr.newFigRenderer(atlasSize, pixelScale))

proc renderFrameBinding*(
    renderer: FigRendererRef, renders: Renders, width, height: float32
) {.raises: [FigDrawError].} =
  if renderer.isNil or renders.isNil:
    return
  withFigDrawError:
    var nodes = renders
    renderer.inner.renderFrame(nodes, vec2(width, height))

when ExportSiwinShim and not defined(emscripten):
  proc newFigSiwinAppBinding*(
      width, height: int32,
      title: string,
      atlasSize: int,
      pixelScale: float32,
      fullscreen: bool,
      vsync: bool,
      msaa: int32,
      resizable: bool,
      frameless: bool,
      transparent: bool,
  ): FigSiwinAppRef {.raises: [FigDrawError].} =
    withFigDrawError:
      when UseVulkanBackend:
        let renderer =
          fgr.newFigRenderer(atlasSize, siwinshim.SiwinRenderBackend(), pixelScale)
        let window = siwinshim.newSiwinWindow(
          renderer,
          ivec2(width, height),
          fullscreen = fullscreen,
          title = title,
          vsync = vsync,
          msaa = msaa,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
        renderer.setupBackend(window)
        result = FigSiwinAppRef(window: window, renderer: renderer)
      else:
        let window = siwinshim.newSiwinWindow(
          ivec2(width, height),
          fullscreen = fullscreen,
          title = title,
          vsync = vsync,
          msaa = msaa,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
        let renderer = fgr.newFigRenderer(
          atlasSize, siwinshim.SiwinRenderBackend(window: window), pixelScale
        )
        renderer.setupBackend(window)
        result = FigSiwinAppRef(window: window, renderer: renderer)
      result.autoScale = result.window.configureUiScale()

  proc siwinFirstStep(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.firstStep()

  proc siwinStep(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.step()

  proc siwinRedraw(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.redraw()

  proc siwinClose(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.close()

  proc siwinOpened(app: FigSiwinAppRef): bool {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return false
    withFigDrawError:
      result = app.window.opened

  proc siwinWindowSize(app: FigSiwinAppRef): WindowSize {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return WindowSize()
    withFigDrawError:
      let size = app.window.size
      result = WindowSize(w: size.x, h: size.y)

  proc siwinBackingSize(app: FigSiwinAppRef): WindowSize {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return WindowSize()
    withFigDrawError:
      let size = app.window.backingSize()
      result = WindowSize(w: size.x, h: size.y)

  proc siwinContentScale(app: FigSiwinAppRef): float32 {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return 1.0'f32
    withFigDrawError:
      result = app.window.contentScale()

  proc siwinRefreshUiScale(app: FigSiwinAppRef) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return
    withFigDrawError:
      app.window.refreshUiScale(app.autoScale)

  proc siwinBackendName(app: FigSiwinAppRef): string {.raises: [FigDrawError].} =
    if app.isNil or app.renderer.isNil:
      return ""
    withFigDrawError:
      result = app.renderer.siwinBackendName()

  proc siwinDisplayServerName(app: FigSiwinAppRef): string {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil:
      return ""
    withFigDrawError:
      result = app.window.siwinDisplayServerName()

  proc renderSiwinFrameBinding*(
      app: FigSiwinAppRef, renders: Renders, width, height: float32
  ) {.raises: [FigDrawError].} =
    if app.isNil or app.renderer.isNil or renders.isNil:
      return
    withFigDrawError:
      app.window.refreshUiScale(app.autoScale)
      app.renderer.beginFrame()
      var nodes = renders
      app.renderer.renderFrame(nodes, vec2(width, height))
      app.renderer.endFrame()

  proc renderSiwinFrameBinding*(
      app: FigSiwinAppRef, renders: Renders
  ) {.raises: [FigDrawError].} =
    if app.isNil or app.window.isNil or renders.isNil:
      return
    withFigDrawError:
      let size = app.window.backingSize()
      renderSiwinFrameBinding(app, renders, size.x.float32, size.y.float32)

proc clear(renders: Renders) =
  returnIfNil renders
  renders.layers.clear()

proc containsLayer(renders: Renders, zLevel: int8): bool =
  if renders.isNil:
    return false
  renders.contains(fdn.ZLevel(zLevel))

proc addRoot(
    renders: Renders, zLevel: int8, root: FigRef
): int16 {.raises: [FigDrawError].} =
  if renders.isNil or root.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.addRoot(fdn.ZLevel(zLevel), root.inner).int16

proc insertRoot(
    renders: Renders, zLevel: int8, rootPos: int, root: FigRef
): int16 {.raises: [FigDrawError].} =
  if renders.isNil or root.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.insertRoot(fdn.ZLevel(zLevel), root.inner, rootPos.Natural).int16

proc addChild(
    renders: Renders, zLevel: int8, parentIdx: int16, child: FigRef
): int16 {.raises: [FigDrawError].} =
  if renders.isNil or child.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result =
      nodes.addChild(fdn.ZLevel(zLevel), fdn.FigIdx(parentIdx), child.inner).int16

proc insertChild(
    renders: Renders, zLevel: int8, parentIdx: int16, childPos: int, child: FigRef
): int16 {.raises: [FigDrawError].} =
  if renders.isNil or child.isNil:
    return -1'i16
  withFigDrawError:
    var nodes = renders
    result = nodes.insertChild(
      fdn.ZLevel(zLevel), fdn.FigIdx(parentIdx), child.inner, childPos.Natural
    ).int16

proc layerNodeCount(renders: Renders, zLevel: int8): int {.raises: [FigDrawError].} =
  if renders.isNil:
    return 0
  try:
    if not renders.containsLayer(zLevel):
      return 0
    result = renders[fdn.ZLevel(zLevel)].nodes.len
  except Exception as e:
    raiseFigDrawError(e)

proc layerRootCount(renders: Renders, zLevel: int8): int {.raises: [FigDrawError].} =
  if renders.isNil:
    return 0
  try:
    if not renders.containsLayer(zLevel):
      return 0
    result = renders[fdn.ZLevel(zLevel)].rootIds.len
  except Exception as e:
    raiseFigDrawError(e)

proc getLayerNode(
    renders: Renders, zLevel: int8, nodeIdx: int16
): FigRef {.raises: [FigDrawError].} =
  if renders.isNil:
    return nil
  try:
    result = FigRef(inner: renders[fdn.ZLevel(zLevel)].nodes[nodeIdx.int])
  except Exception as e:
    raiseFigDrawError(e)

exportProcs:
  checkError
  takeError

exportEnums:
  FillKind
  FillGradientAxis
  FigFlags
  FontCase
  DirectionCorners
  ShadowStyle

exportObject ColorRGBA:
  constructor:
    colorRgba(uint8, uint8, uint8, uint8)

exportObject CornerRadii:
  constructor:
    cornerRadii(float32, float32, float32, float32)

exportObject ScreenBox:
  discard

exportObject WindowSize:
  discard

exportRefObject FigRef:
  constructor:
    newFig()
  procs:
    copy(FigRef)
    kind(FigRef)
    setKind(FigRef, int8)
    zLevel(FigRef)
    setZLevel(FigRef, int8)
    childCount(FigRef)
    parentIndex(FigRef)
    hasFlag(FigRef, FigFlags)
    setFlag(FigRef, FigFlags, bool)
    clearFlags(FigRef)
    getScreenBox(FigRef)
    setScreenBox(FigRef, float32, float32, float32, float32)
    setFillColor(FigRef, uint8, uint8, uint8, uint8)
    setFillColorRgba(FigRef, ColorRGBA)
    setFillLinear2(FigRef, ColorRGBA, ColorRGBA, FillGradientAxis)
    setFillLinear3(FigRef, ColorRGBA, ColorRGBA, ColorRGBA, FillGradientAxis, uint8)
    fillKind(FigRef)
    fillColor(FigRef)
    fillLinear2Start(FigRef)
    fillLinear2Stop(FigRef)
    fillLinear2Axis(FigRef)
    fillLinear3Start(FigRef)
    fillLinear3Mid(FigRef)
    fillLinear3Stop(FigRef)
    fillLinear3Axis(FigRef)
    fillLinear3MidPos(FigRef)
    rotation(FigRef)
    setRotation(FigRef, float32)
    getCorners(FigRef)
    setCorners(FigRef, CornerRadii)
    setStroke(FigRef, float32, ColorRGBA)
    strokeWeight(FigRef)
    strokeColor(FigRef)
    clearShadows(FigRef)
    setShadow(FigRef, int8, ShadowStyle, float32, float32, float32, float32, ColorRGBA)
    shadowStyle(FigRef, int8)
    shadowBlur(FigRef, int8)
    shadowSpread(FigRef, int8)
    shadowX(FigRef, int8)
    shadowY(FigRef, int8)
    shadowColor(FigRef, int8)
    setSelectionRange(FigRef, int16, int16)
    selectionFirst(FigRef)
    selectionLast(FigRef)
    clearDrawablePoints(FigRef)
    addDrawablePoint(FigRef, float32, float32)
    drawablePointCount(FigRef)
    drawablePointX(FigRef, int)
    drawablePointY(FigRef, int)
    setDrawablePoint(FigRef, int, float32, float32)
    imageId(FigRef)
    setImageId(FigRef, int64)
    setImageFillColorRgba(FigRef, ColorRGBA)
    setImageFillLinear2(FigRef, ColorRGBA, ColorRGBA, FillGradientAxis)
    setImageFillLinear3(
      FigRef, ColorRGBA, ColorRGBA, ColorRGBA, FillGradientAxis, uint8
    )
    imageFillKind(FigRef)
    imageFillColor(FigRef)
    imageFillLinear2Start(FigRef)
    imageFillLinear2Stop(FigRef)
    imageFillLinear2Axis(FigRef)
    imageFillLinear3Start(FigRef)
    imageFillLinear3Mid(FigRef)
    imageFillLinear3Stop(FigRef)
    imageFillLinear3Axis(FigRef)
    imageFillLinear3MidPos(FigRef)
    setMsdfImage(FigRef, int64, float32, float32, float32)
    msdfImageId(FigRef)
    msdfImagePxRange(FigRef)
    msdfImageSdThreshold(FigRef)
    msdfImageStrokeWeight(FigRef)
    setMsdfImageFillColorRgba(FigRef, ColorRGBA)
    setMsdfImageFillLinear2(FigRef, ColorRGBA, ColorRGBA, FillGradientAxis)
    setMsdfImageFillLinear3(
      FigRef, ColorRGBA, ColorRGBA, ColorRGBA, FillGradientAxis, uint8
    )
    msdfImageFillKind(FigRef)
    msdfImageFillColor(FigRef)
    msdfImageFillLinear2Start(FigRef)
    msdfImageFillLinear2Stop(FigRef)
    msdfImageFillLinear2Axis(FigRef)
    msdfImageFillLinear3Start(FigRef)
    msdfImageFillLinear3Mid(FigRef)
    msdfImageFillLinear3Stop(FigRef)
    msdfImageFillLinear3Axis(FigRef)
    msdfImageFillLinear3MidPos(FigRef)
    setMtsdfImage(FigRef, int64, float32, float32, float32)
    mtsdfImageId(FigRef)
    mtsdfImagePxRange(FigRef)
    mtsdfImageSdThreshold(FigRef)
    mtsdfImageStrokeWeight(FigRef)
    setMtsdfImageFillColorRgba(FigRef, ColorRGBA)
    setMtsdfImageFillLinear2(FigRef, ColorRGBA, ColorRGBA, FillGradientAxis)
    setMtsdfImageFillLinear3(
      FigRef, ColorRGBA, ColorRGBA, ColorRGBA, FillGradientAxis, uint8
    )
    mtsdfImageFillKind(FigRef)
    mtsdfImageFillColor(FigRef)
    mtsdfImageFillLinear2Start(FigRef)
    mtsdfImageFillLinear2Stop(FigRef)
    mtsdfImageFillLinear2Axis(FigRef)
    mtsdfImageFillLinear3Start(FigRef)
    mtsdfImageFillLinear3Mid(FigRef)
    mtsdfImageFillLinear3Stop(FigRef)
    mtsdfImageFillLinear3Axis(FigRef)
    mtsdfImageFillLinear3MidPos(FigRef)
    setBackdropBlur(FigRef, float32)
    backdropBlur(FigRef)
    setTransformTranslation(FigRef, float32, float32)
    transformTranslationX(FigRef)
    transformTranslationY(FigRef)
    transformUseMatrix(FigRef)
    setTransformUseMatrix(FigRef, bool)
    setTransformMatrix(
      FigRef, float32, float32, float32, float32, float32, float32, float32, float32,
      float32, float32, float32, float32, float32, float32, float32, float32,
    )
    transformMatrixValue(FigRef, int8, int8)

exportRefObject Renders:
  constructor:
    newRenders()
  procs:
    clear(Renders)
    containsLayer(Renders, int8)
    addRoot(Renders, int8, FigRef)
    insertRoot(Renders, int8, int, FigRef)
    addChild(Renders, int8, int16, FigRef)
    insertChild(Renders, int8, int16, int, FigRef)
    layerNodeCount(Renders, int8)
    layerRootCount(Renders, int8)
    getLayerNode(Renders, int8, int16)

exportRefObject FigRendererRef:
  constructor:
    newFigRendererBinding(int, float32)
  procs:
    renderFrameBinding(FigRendererRef, Renders, float32, float32)

when ExportSiwinShim and not defined(emscripten):
  exportRefObject FigSiwinAppRef:
    constructor:
      newFigSiwinAppBinding(
        int32, int32, string, int, float32, bool, bool, int32, bool, bool, bool
      )
    procs:
      siwinFirstStep(FigSiwinAppRef)
      siwinStep(FigSiwinAppRef)
      siwinRedraw(FigSiwinAppRef)
      siwinClose(FigSiwinAppRef)
      siwinOpened(FigSiwinAppRef)
      siwinWindowSize(FigSiwinAppRef)
      siwinBackingSize(FigSiwinAppRef)
      siwinContentScale(FigSiwinAppRef)
      siwinRefreshUiScale(FigSiwinAppRef)
      siwinBackendName(FigSiwinAppRef)
      siwinDisplayServerName(FigSiwinAppRef)
      renderSiwinFrameBinding(FigSiwinAppRef, Renders, float32, float32)
      renderSiwinFrameBinding(FigSiwinAppRef, Renders)

exportRefObject TypefaceRef:
  discard

exportRefObject FigFontRef:
  constructor:
    newFigFontBinding(TypefaceRef, float32)
  procs:
    setFigFontLineHeightBinding(FigFontRef, float32)
    setFigFontCaseBinding(FigFontRef, FontCase)

exportRefObject GlyphLayoutRef:
  procs:
    textLayoutWidthBinding(GlyphLayoutRef)
    textLayoutHeightBinding(GlyphLayoutRef)

exportProcs:
  newRectangleFig
  newTextFig
  newDrawableFig
  newImageFig
  newMsdfImageFig
  newMtsdfImageFig
  newBackdropBlurFig
  newTransformFig
  loadTypefaceBinding
  typesetTextBinding
  setFigTextLayoutBinding
  figDataDir
  setFigDataDir
  figUiScale
  setFigUiScale
  scaled(float32)
  descaled(float32)

writeFiles(GeneratedDir, "Figdraw")

include generated/internal
