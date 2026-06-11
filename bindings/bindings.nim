import genny
import std/tables
import std/hashes
import vmath
import std/os
import figdraw/commons
import figdraw/fignodes as fdn
import figdraw/figrender as fgr
import figdraw/common/fonttypes as fnt
from figdraw/common/fonttypes import FontCase
import figdraw/common/fontutils as fut
when not defined(emscripten):
  import figdraw/utils/glutils

const ExportSiwinShim* {.booldefine: "figdraw.bindings.siwinshim".} = false
const GeneratedDir = currentSourcePath().parentDir / "generated"

type
  CornerRadii* = object
    topLeft*: float32
    topRight*: float32
    bottomLeft*: float32
    bottomRight*: float32

  BorderSize* = object
    width*: float32

  Fig* = ref object
    inner: fdn.Fig

  RenderList* = ref object
    inner: fdn.RenderList

  Renders* = ref object
    inner: fdn.Renders

  FigRendererRef* = ref object
    inner: fgr.FigRenderer[fgr.NoRendererBackendState]

  TypefaceRef* = ref object
    id: fnt.TypefaceId

  FigFontRef* = ref object
    inner: fnt.FigFont

  GlyphLayoutRef* = ref object
    inner: fnt.GlyphArrangement

proc newFig(): Fig =
  Fig(inner: fdn.Fig(kind: fdn.nkFrame))

proc initRgba(r, g, b, a: uint8): ColorRGBA =
  rgba(r, g, b, a)

proc newCornerRadii(topLeft, topRight, bottomLeft, bottomRight: float32): CornerRadii =
  CornerRadii(
    topLeft: topLeft,
    topRight: topRight,
    bottomLeft: bottomLeft,
    bottomRight: bottomRight,
  )

proc newBorderSize(width: float32): BorderSize =
  BorderSize(width: width)

func toFigKind(kind: int8): fdn.FigKind =
  let raw = kind.int
  if raw < ord(low(fdn.FigKind)) or raw > ord(high(fdn.FigKind)):
    fdn.nkFrame
  else:
    fdn.FigKind(raw)

proc newRectangleFig(x, y, w, h: float32): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkRectangle,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
    )
  )

proc newTextFig(x, y, w, h: float32): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkText,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      textLayout: GlyphArrangement(),
    )
  )

proc newImageFig(x, y, w, h: float32, imageId: int64): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkImage,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      image: ImageStyle(
        id: cast[ImageId](Hash(imageId)), fill: fill(rgba(255, 255, 255, 255))
      ),
    )
  )

proc newTransformFig(x, y, w, h: float32, tx, ty: float32): Fig =
  Fig(
    inner: fdn.Fig(
      kind: fdn.nkTransform,
      screenBox: rect(x, y, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
      transform: TransformStyle(translation: vec2(tx, ty), useMatrix: false),
    )
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

proc setFigFontCaseBinding(font: FigFontRef, fontCase: FontCase) =
  if font.isNil:
    return
  font.inner.fontCase = fontCase

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

proc figWithKind(src: fdn.Fig, kind: fdn.FigKind): fdn.Fig

proc setFigTextLayoutBinding(fig: Fig, layout: GlyphLayoutRef) =
  if fig.isNil or layout.isNil:
    return
  try:
    if fig.inner.kind != fdn.nkText:
      fig.inner = figWithKind(fig.inner, fdn.nkText)
    fig.inner.textLayout = layout.inner
  except Exception:
    discard

proc textLayoutWidthBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.w

proc textLayoutHeightBinding(layout: GlyphLayoutRef): float32 =
  if layout.isNil:
    return 0'f32
  layout.inner.bounding.h

proc copy(fig: Fig): Fig =
  if fig.isNil:
    return nil
  Fig(inner: fig.inner)

proc figWithKind(src: fdn.Fig, kind: fdn.FigKind): fdn.Fig =
  result = fdn.Fig(kind: kind)
  result.zlevel = src.zlevel
  result.parent = src.parent
  result.flags = src.flags
  result.childCount = src.childCount
  result.screenBox = src.screenBox
  result.rotation = src.rotation
  result.fill = src.fill
  result.corners = src.corners

proc ensureRectangle(fig: Fig) =
  if fig.isNil:
    return
  if fig.inner.kind != fdn.nkRectangle:
    fig.inner = figWithKind(fig.inner, fdn.nkRectangle)

proc kind(fig: Fig): int8 =
  if fig.isNil:
    return fdn.nkFrame.int8
  fig.inner.kind.int8

proc setKind(fig: Fig, kind: int8) =
  if fig.isNil:
    return
  fig.inner = figWithKind(fig.inner, kind.toFigKind())

proc zLevel(fig: Fig): int8 =
  if fig.isNil:
    return 0'i8
  fig.inner.zlevel.int8

proc setZLevel(fig: Fig, zLevel: int8) =
  if fig.isNil:
    return
  fig.inner.zlevel = fdn.ZLevel(zLevel)

proc x(fig: Fig): float32 =
  if fig.isNil:
    return 0'f32
  fig.inner.screenBox.x

proc y(fig: Fig): float32 =
  if fig.isNil:
    return 0'f32
  fig.inner.screenBox.y

proc width(fig: Fig): float32 =
  if fig.isNil:
    return 0'f32
  fig.inner.screenBox.w

proc height(fig: Fig): float32 =
  if fig.isNil:
    return 0'f32
  fig.inner.screenBox.h

proc setScreenBox(fig: Fig, x, y, w, h: float32) =
  if fig.isNil:
    return
  fig.inner.screenBox = rect(x, y, w, h)

proc setFillColor(fig: Fig, r, g, b, a: uint8) =
  if fig.isNil:
    return
  fig.inner.fill = fill(rgba(r, g, b, a))

proc setFillColorRgba(fig: Fig, color: ColorRGBA) =
  if fig.isNil:
    return
  fig.inner.fill = fill(color)

proc setFillLinear2Raw(
    fig: Fig, sr, sg, sb, sa: uint8, er, eg, eb, ea: uint8, axis: FillGradientAxis
) =
  if fig.isNil:
    return
  fig.inner.fill = linear(
    rgba(sr, sg, sb, sa),
    rgba(er, eg, eb, ea),
    axis = axis,
  )

proc setFillLinear2(fig: Fig, startColor, endColor: ColorRGBA, axis: FillGradientAxis) =
  if fig.isNil:
    return
  fig.inner.fill = linear(
    startColor,
    endColor,
    axis = axis,
  )

proc setFillLinear3Raw(
    fig: Fig,
    sr, sg, sb, sa: uint8,
    mr, mg, mb, ma: uint8,
    er, eg, eb, ea: uint8,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  if fig.isNil:
    return
  fig.inner.fill = linear(
    rgba(sr, sg, sb, sa),
    rgba(mr, mg, mb, ma),
    rgba(er, eg, eb, ea),
    axis = axis,
    midPos = midPos,
  )

proc setFillLinear3(
    fig: Fig,
    startColor, midColor, endColor: ColorRGBA,
    axis: FillGradientAxis,
    midPos: uint8,
) =
  if fig.isNil:
    return
  fig.inner.fill = linear(
    startColor,
    midColor,
    endColor,
    axis = axis,
    midPos = midPos,
  )

proc setRotation(fig: Fig, rotation: float32) =
  if fig.isNil:
    return
  fig.inner.rotation = rotation

proc setCornersRaw(fig: Fig, topLeft, topRight, bottomLeft, bottomRight: float32) =
  if fig.isNil:
    return
  fig.inner.corners = [topLeft, topRight, bottomLeft, bottomRight]

proc setCorners(fig: Fig, radii: CornerRadii) =
  if fig.isNil:
    return
  fig.inner.corners =
    [radii.topLeft, radii.topRight, radii.bottomLeft, radii.bottomRight]

proc setStrokeRaw(fig: Fig, weight: float32, r, g, b, a: uint8) =
  if fig.isNil:
    return
  fig.ensureRectangle()
  fig.inner.stroke = RenderStroke(weight: weight, fill: fill(rgba(r, g, b, a)))

proc setStrokeRaw(fig: Fig, weight: float32, color: ColorRGBA) =
  if fig.isNil:
    return
  fig.ensureRectangle()
  fig.inner.stroke = RenderStroke(weight: weight, fill: fill(color))

proc setStroke(fig: Fig, border: BorderSize, color: ColorRGBA) =
  if fig.isNil:
    return
  fig.ensureRectangle()
  fig.inner.stroke = RenderStroke(weight: border.width, fill: fill(color))

proc clearShadows(fig: Fig) =
  if fig.isNil:
    return
  fig.ensureRectangle()
  fig.inner.shadows = [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()]

proc setShadowRaw(
    fig: Fig,
    shadowIndex: int8,
    style: ShadowStyle,
    blur, spread, x, y: float32,
    r, g, b, a: uint8,
) =
  if fig.isNil:
    return
  fig.ensureRectangle()
  if shadowIndex < 0'i8 or shadowIndex >= ShadowCount.int8:
    return

  fig.inner.shadows[shadowIndex.int] = RenderShadow(
    style: style,
    blur: blur,
    spread: spread,
    x: x,
    y: y,
    fill: fill(rgba(r, g, b, a)),
  )

proc setShadow(
    fig: Fig,
    shadowIndex: int8,
    style: ShadowStyle,
    blur, spread, x, y: float32,
    color: ColorRGBA,
) =
  if fig.isNil:
    return
  fig.ensureRectangle()
  if shadowIndex < 0'i8 or shadowIndex >= ShadowCount.int8:
    return

  fig.inner.shadows[shadowIndex.int] = RenderShadow(
    style: style,
    blur: blur,
    spread: spread,
    x: x,
    y: y,
    fill: fill(color),
  )

proc newRenderList(): RenderList =
  RenderList(inner: fdn.RenderList())

proc copy(list: RenderList): RenderList =
  if list.isNil:
    return nil
  RenderList(inner: list.inner)

proc clear(list: RenderList) =
  if list.isNil:
    return
  list.inner = fdn.RenderList()

proc nodeCount(list: RenderList): int =
  if list.isNil:
    return 0
  list.inner.nodes.len

proc rootCount(list: RenderList): int =
  if list.isNil:
    return 0
  list.inner.rootIds.len

proc addRoot(list: RenderList, root: Fig): int16 =
  if list.isNil or root.isNil:
    return -1'i16
  list.inner.addRoot(root.inner).int16

proc addChild(list: RenderList, parentIdx: int16, child: Fig): int16 =
  if list.isNil or child.isNil:
    return -1'i16
  try:
    list.inner.addChild(fdn.FigIdx(parentIdx), child.inner).int16
  except ValueError:
    -1'i16

proc getNode(list: RenderList, nodeIdx: int16): Fig =
  if list.isNil:
    return nil
  try:
    Fig(inner: list.inner.nodes[nodeIdx.int])
  except CatchableError:
    nil

proc getRootId(list: RenderList, rootIdx: int16): int16 =
  if list.isNil:
    return -1'i16
  try:
    list.inner.rootIds[rootIdx.int].int16
  except CatchableError:
    -1'i16

proc newRenders(): Renders =
  Renders(inner: fdn.Renders(layers: initOrderedTable[fdn.ZLevel, fdn.RenderList]()))

proc ensureOpenGLInitialized() =
  when not defined(emscripten):
    startOpenGL(openglVersion)

proc newFigRendererBinding*(atlasSize: int, pixelScale: float32): FigRendererRef =
  try:
    ensureOpenGLInitialized()
    FigRendererRef(inner: fgr.newFigRenderer(atlasSize, pixelScale))
  except Exception:
    nil

proc renderFrameBinding*(renderer: FigRendererRef, renders: Renders, width, height: float32) =
  if renderer.isNil or renders.isNil:
    return
  try:
    renderer.inner.renderFrame(renders.inner, vec2(width, height))
  except Exception:
    discard

proc clear(renders: Renders) =
  if renders.isNil:
    return
  renders.inner.layers.clear()

proc containsLayer(renders: Renders, zLevel: int8): bool =
  if renders.isNil:
    return false
  renders.inner.contains(fdn.ZLevel(zLevel))

proc addRoot(renders: Renders, zLevel: int8, root: Fig): int16 =
  if renders.isNil or root.isNil:
    return -1'i16
  try:
    renders.inner.addRoot(fdn.ZLevel(zLevel), root.inner).int16
  except CatchableError:
    -1'i16

proc addChild(renders: Renders, zLevel: int8, parentIdx: int16, child: Fig): int16 =
  if renders.isNil or child.isNil:
    return -1'i16
  try:
    renders.inner.addChild(fdn.ZLevel(zLevel), fdn.FigIdx(parentIdx), child.inner).int16
  except CatchableError:
    -1'i16

proc layerNodeCount(renders: Renders, zLevel: int8): int =
  if renders.isNil:
    return 0
  try:
    if not renders.containsLayer(zLevel):
      return 0
    renders.inner[fdn.ZLevel(zLevel)].nodes.len
  except CatchableError:
    0

proc layerRootCount(renders: Renders, zLevel: int8): int =
  if renders.isNil:
    return 0
  try:
    if not renders.containsLayer(zLevel):
      return 0
    renders.inner[fdn.ZLevel(zLevel)].rootIds.len
  except CatchableError:
    0

proc getLayerNode(renders: Renders, zLevel: int8, nodeIdx: int16): Fig =
  if renders.isNil:
    return nil
  try:
    Fig(inner: renders.inner[fdn.ZLevel(zLevel)].nodes[nodeIdx.int])
  except CatchableError:
    nil

exportObject chroma.ColorRGBA:
  constructor:
    initRgba(uint8, uint8, uint8, uint8)

exportObject CornerRadii:
  constructor:
    newCornerRadii(float32, float32, float32, float32)

exportObject BorderSize:
  constructor:
    newBorderSize(float32)

exportEnums:
  FillGradientAxis
  FontCase
  ShadowStyle

exportRefObject Fig:
  constructor:
    newFig()
  procs:
    copy(Fig)
    kind(Fig)
    setKind(Fig, int8)
    zLevel(Fig)
    setZLevel(Fig, int8)
    x(Fig)
    y(Fig)
    width(Fig)
    height(Fig)
    setScreenBox(Fig, float32, float32, float32, float32)
    setFillColor(Fig, uint8, uint8, uint8, uint8)
    setFillColorRgba(Fig, ColorRGBA)
    setFillLinear2(Fig, ColorRGBA, ColorRGBA, FillGradientAxis)
    setFillLinear3(Fig, ColorRGBA, ColorRGBA, ColorRGBA, FillGradientAxis, uint8)
    setRotation(Fig, float32)
    setCorners(Fig, CornerRadii)
    setStroke(Fig, BorderSize, ColorRGBA)
    clearShadows(Fig)
    setShadow(Fig, int8, ShadowStyle, float32, float32, float32, float32, ColorRGBA)

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

exportRefObject FigRendererRef:
  constructor:
    newFigRendererBinding(int, float32)
  procs:
    renderFrameBinding(FigRendererRef, Renders, float32, float32)

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

writeFiles(GeneratedDir, "Figdraw")

include generated/internal
