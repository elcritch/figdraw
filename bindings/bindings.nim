import genny
import std/tables
import std/hashes
import figdraw/commons
import figdraw/fignodes as fdn
import figdraw/common/fonttypes as fnt
import figdraw/common/fontutils as fut

const ExportSiwinShim* {.booldefine: "figdraw.bindings.siwinshim".} = false

type
  FigKind* = fdn.FigKind

  RgbaColor* = object
    r*: uint8
    g*: uint8
    b*: uint8
    a*: uint8

  Fig* = ref object
    inner: fdn.Fig

  RenderList* = ref object
    inner: fdn.RenderList

  Renders* = ref object
    inner: fdn.Renders

  TypefaceRef* = ref object
    id: fnt.TypefaceId

  FigFontRef* = ref object
    inner: fnt.FigFont

  GlyphLayoutRef* = ref object
    inner: fnt.GlyphArrangement

proc newFig(): Fig =
  Fig(inner: fdn.Fig(kind: fdn.nkFrame))

proc newRgbaColor(r, g, b, a: uint8): RgbaColor =
  RgbaColor(r: r, g: g, b: b, a: a)

proc newRectangleFig(x, y, w, h: float32): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkRectangle,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
    ),
  )

proc newTextFig(x, y, w, h: float32): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkText,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      textLayout: GlyphArrangement(),
    ),
  )

proc newImageFig(x, y, w, h: float32, imageId: int64): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkImage,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      image: ImageStyle(
        id: cast[ImageId](Hash(imageId)),
        fill: fill(rgba(255, 255, 255, 255)),
      ),
    ),
  )

proc newTransformFig(x, y, w, h: float32, tx, ty: float32): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkTransform,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      transform: TransformStyle(
        translation: vec2(tx, ty),
        useMatrix: false,
      ),
    ),
  )

proc loadTypefaceBinding(name: string): TypefaceRef =
  try:
    let fontId = fut.loadTypeface(name)
    TypefaceRef(id: cast[fnt.TypefaceId](fontId))
  except CatchableError:
    nil

proc newFigFontBinding(typeface: TypefaceRef, size: float32): FigFontRef =
  if typeface.isNil:
    return nil
  FigFontRef(inner: fnt.FigFont(typefaceId: typeface.id, size: size))

proc setFigFontLineHeightBinding(font: FigFontRef, lineHeight: float32) =
  if font.isNil:
    return
  font.inner.lineHeight = lineHeight

proc setFigFontCaseBinding(font: FigFontRef, fontCase: int8) =
  if font.isNil:
    return
  case fontCase
  of 1'i8:
    font.inner.fontCase = fnt.FontCase.UpperCase
  of 2'i8:
    font.inner.fontCase = fnt.FontCase.LowerCase
  of 3'i8:
    font.inner.fontCase = fnt.FontCase.TitleCase
  else:
    font.inner.fontCase = fnt.FontCase.NormalCase

proc typesetTextBinding(
    width, height: float32,
    font: FigFontRef,
    text: string,
    hAlign: int8 = 0,
    vAlign: int8 = 0,
    minContent = false,
    wrap = false,
): GlyphLayoutRef =
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
    GlyphLayoutRef(inner: layout)
  except CatchableError:
    nil

proc setFigTextLayoutBinding(fig: Fig, layout: GlyphLayoutRef) =
  if fig.isNil or layout.isNil:
    return
  if fig.inner.kind != fdn.nkText:
    fig.inner.kind = fdn.nkText
  fig.inner.textLayout = layout.inner

proc textLayoutWidthBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.w

proc textLayoutHeightBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.h

proc copy(fig: Fig): Fig =
  Fig(inner: fig.inner)

proc figWithKind(src: fdn.Fig, kind: FigKind): fdn.Fig =
  result = fdn.Fig(kind: fdn.FigKind(kind))
  result.zlevel = src.zlevel
  result.parent = src.parent
  result.flags = src.flags
  result.childCount = src.childCount
  result.screenBox = src.screenBox
  result.rotation = src.rotation
  result.fill = src.fill
  result.corners = src.corners

proc kind(fig: Fig): FigKind =
  fig.inner.kind

proc setKind(fig: Fig, kind: FigKind) =
  fig.inner = figWithKind(fig.inner, kind)

proc zLevel(fig: Fig): int8 =
  fig.inner.zlevel.int8

proc setZLevel(fig: Fig, zLevel: int8) =
  fig.inner.zlevel = fdn.ZLevel(zLevel)

proc x(fig: Fig): float32 =
  fig.inner.screenBox.x

proc y(fig: Fig): float32 =
  fig.inner.screenBox.y

proc width(fig: Fig): float32 =
  fig.inner.screenBox.w

proc height(fig: Fig): float32 =
  fig.inner.screenBox.h

proc setScreenBox(fig: Fig, x, y, w, h: float32) =
  fig.inner.screenBox = rect(x, y, w, h)

proc setFillColor(fig: Fig, r, g, b, a: uint8) =
  fig.inner.fill = fill(rgba(r, g, b, a))

proc setFillColorRgba(fig: Fig, color: RgbaColor) =
  fig.inner.fill = fill(rgba(color.r, color.g, color.b, color.a))

proc parseFillAxis(axis: int8): FillGradientAxis =
  case axis
  of 1'i8:
    fgaY
  of 2'i8:
    fgaDiagTLBR
  of 3'i8:
    fgaDiagBLTR
  else:
    fgaX

proc setFillLinear2(
    fig: Fig,
    sr, sg, sb, sa: uint8,
    er, eg, eb, ea: uint8,
    axis: int8,
) =
  fig.inner.fill = linear(
    rgba(sr, sg, sb, sa),
    rgba(er, eg, eb, ea),
    axis = parseFillAxis(axis),
  )

proc setFillLinear2Rgba(
    fig: Fig,
    startColor, endColor: RgbaColor,
    axis: int8,
) =
  fig.inner.fill = linear(
    rgba(startColor.r, startColor.g, startColor.b, startColor.a),
    rgba(endColor.r, endColor.g, endColor.b, endColor.a),
    axis = parseFillAxis(axis),
  )

proc setFillLinear3(
    fig: Fig,
    sr, sg, sb, sa: uint8,
    mr, mg, mb, ma: uint8,
    er, eg, eb, ea: uint8,
    axis: int8,
    midPos: uint8,
) =
  fig.inner.fill = linear(
    rgba(sr, sg, sb, sa),
    rgba(mr, mg, mb, ma),
    rgba(er, eg, eb, ea),
    axis = parseFillAxis(axis),
    midPos = midPos,
  )

proc setFillLinear3Rgba(
    fig: Fig,
    startColor, midColor, endColor: RgbaColor,
    axis: int8,
    midPos: uint8,
) =
  fig.inner.fill = linear(
    rgba(startColor.r, startColor.g, startColor.b, startColor.a),
    rgba(midColor.r, midColor.g, midColor.b, midColor.a),
    rgba(endColor.r, endColor.g, endColor.b, endColor.a),
    axis = parseFillAxis(axis),
    midPos = midPos,
  )

proc setRotation(fig: Fig, rotation: float32) =
  fig.inner.rotation = rotation

proc setCorners(fig: Fig, topLeft, topRight, bottomLeft, bottomRight: float32) =
  fig.inner.corners = [topLeft, topRight, bottomLeft, bottomRight]

proc setStroke(fig: Fig, weight: float32, r, g, b, a: uint8) =
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)
  fig.inner.stroke = RenderStroke(
    weight: weight,
    fill: fill(rgba(r, g, b, a)),
  )

proc setStrokeRgba(fig: Fig, weight: float32, color: RgbaColor) =
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)
  fig.inner.stroke = RenderStroke(
    weight: weight,
    fill: fill(rgba(color.r, color.g, color.b, color.a)),
  )

proc clearShadows(fig: Fig) =
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)
  fig.inner.shadows = [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()]

proc setShadow(
    fig: Fig,
    shadowIndex: int8,
    style: int8,
    blur, spread, x, y: float32,
    r, g, b, a: uint8,
) =
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)
  if shadowIndex < 0'i8 or shadowIndex >= ShadowCount.int8:
    return

  var shadowStyle = ShadowStyle.NoShadow
  case style
  of 1'i8:
    shadowStyle = ShadowStyle.DropShadow
  of 2'i8:
    shadowStyle = ShadowStyle.InnerShadow
  else:
    discard

  fig.inner.shadows[shadowIndex.int] = RenderShadow(
    style: shadowStyle,
    blur: blur,
    spread: spread,
    x: x,
    y: y,
    fill: fill(rgba(r, g, b, a)),
  )

proc setShadowRgba(
    fig: Fig,
    shadowIndex: int8,
    style: int8,
    blur, spread, x, y: float32,
    color: RgbaColor,
) =
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)
  if shadowIndex < 0'i8 or shadowIndex >= ShadowCount.int8:
    return

  var shadowStyle = ShadowStyle.NoShadow
  case style
  of 1'i8:
    shadowStyle = ShadowStyle.DropShadow
  of 2'i8:
    shadowStyle = ShadowStyle.InnerShadow
  else:
    discard

  fig.inner.shadows[shadowIndex.int] = RenderShadow(
    style: shadowStyle,
    blur: blur,
    spread: spread,
    x: x,
    y: y,
    fill: fill(rgba(color.r, color.g, color.b, color.a)),
  )

proc newRenderList(): RenderList =
  RenderList(inner: fdn.RenderList())

proc copy(list: RenderList): RenderList =
  RenderList(inner: list.inner)

proc clear(list: RenderList) =
  list.inner = fdn.RenderList()

proc nodeCount(list: RenderList): int =
  list.inner.nodes.len

proc rootCount(list: RenderList): int =
  list.inner.rootIds.len

proc addRoot(list: RenderList, root: Fig): int16 =
  list.inner.addRoot(root.inner).int16

proc addChild(list: RenderList, parentIdx: int16, child: Fig): int16 =
  try:
    list.inner.addChild(fdn.FigIdx(parentIdx), child.inner).int16
  except ValueError:
    -1'i16

proc getNode(list: RenderList, nodeIdx: int16): Fig =
  Fig(inner: list.inner.nodes[nodeIdx.int])

proc getRootId(list: RenderList, rootIdx: int16): int16 =
  list.inner.rootIds[rootIdx.int].int16

proc newRenders(): Renders =
  Renders(inner: fdn.Renders(layers: initOrderedTable[fdn.ZLevel, fdn.RenderList]()))

proc clear(renders: Renders) =
  renders.inner.layers.clear()

proc containsLayer(renders: Renders, zLevel: int8): bool =
  renders.inner.contains(fdn.ZLevel(zLevel))

proc addRoot(renders: Renders, zLevel: int8, root: Fig): int16 =
  try:
    renders.inner.addRoot(fdn.ZLevel(zLevel), root.inner).int16
  except CatchableError:
    -1'i16

proc addChild(renders: Renders, zLevel: int8, parentIdx: int16, child: Fig): int16 =
  try:
    renders.inner.addChild(
      fdn.ZLevel(zLevel),
      fdn.FigIdx(parentIdx),
      child.inner,
    ).int16
  except CatchableError:
    -1'i16

proc layerNodeCount(renders: Renders, zLevel: int8): int =
  try:
    if not renders.containsLayer(zLevel):
      return 0
    renders.inner[fdn.ZLevel(zLevel)].nodes.len
  except CatchableError:
    0

proc layerRootCount(renders: Renders, zLevel: int8): int =
  try:
    if not renders.containsLayer(zLevel):
      return 0
    renders.inner[fdn.ZLevel(zLevel)].rootIds.len
  except CatchableError:
    0

proc getLayerNode(renders: Renders, zLevel: int8, nodeIdx: int16): Fig =
  try:
    Fig(inner: renders.inner[fdn.ZLevel(zLevel)].nodes[nodeIdx.int])
  except CatchableError:
    newFig()

exportEnums:
  FigKind

exportObject RgbaColor:
  constructor:
    newRgbaColor(uint8, uint8, uint8, uint8)

exportRefObject Fig:
  constructor:
    newFig()
  procs:
    copy(Fig)
    kind(Fig)
    setKind(Fig, FigKind)
    zLevel(Fig)
    setZLevel(Fig, int8)
    x(Fig)
    y(Fig)
    width(Fig)
    height(Fig)
    setScreenBox(Fig, float32, float32, float32, float32)
    setFillColor(Fig, uint8, uint8, uint8, uint8)
    setFillColorRgba(Fig, RgbaColor)
    setFillLinear2(
      Fig,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      int8,
    )
    setFillLinear2Rgba(Fig, RgbaColor, RgbaColor, int8)
    setFillLinear3(
      Fig,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      uint8,
      int8,
      uint8,
    )
    setFillLinear3Rgba(Fig, RgbaColor, RgbaColor, RgbaColor, int8, uint8)
    setRotation(Fig, float32)
    setCorners(Fig, float32, float32, float32, float32)
    setStroke(Fig, float32, uint8, uint8, uint8, uint8)
    setStrokeRgba(Fig, float32, RgbaColor)
    clearShadows(Fig)
    setShadow(
      Fig,
      int8,
      int8,
      float32,
      float32,
      float32,
      float32,
      uint8,
      uint8,
      uint8,
      uint8,
    )
    setShadowRgba(Fig, int8, int8, float32, float32, float32, float32, RgbaColor)

exportRefObject RenderList:
  constructor:
    newRenderList()
  procs:
    copy(RenderList)
    clear(RenderList)
    nodeCount(RenderList)
    rootCount(RenderList)
    addRoot(RenderList, Fig)
    addChild(RenderList, int16, Fig)
    getNode(RenderList, int16)
    getRootId(RenderList, int16)

exportRefObject Renders:
  constructor:
    newRenders()
  procs:
    clear(Renders)
    containsLayer(Renders, int8)
    addRoot(Renders, int8, Fig)
    addChild(Renders, int8, int16, Fig)
    layerNodeCount(Renders, int8)
    layerRootCount(Renders, int8)
    getLayerNode(Renders, int8, int16)

exportRefObject TypefaceRef:
  discard

exportRefObject FigFontRef:
  constructor:
    newFigFontBinding(TypefaceRef, float32)
  procs:
    setFigFontLineHeightBinding(FigFontRef, float32)
    setFigFontCaseBinding(FigFontRef, int8)

exportRefObject GlyphLayoutRef:
  procs:
    textLayoutWidthBinding(GlyphLayoutRef)
    textLayoutHeightBinding(GlyphLayoutRef)

exportProcs:
  newRectangleFig
  newTextFig
  newImageFig
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

when ExportSiwinShim:
  include siwinshim_bindings

writeFiles("bindings/generated", "FigDraw")

include generated/internal
