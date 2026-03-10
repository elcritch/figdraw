import genny
import std/tables
import std/hashes
import figdraw/commons
import figdraw/fignodes as fdn

const ExportSiwinShim* {.booldefine: "figdraw.bindings.siwinshim".} = false

when ExportSiwinShim:
  import figdraw/windowing/siwinshim

type
  FigKind* = fdn.FigKind
  ZLevel* = int8

  Fig* = ref object
    inner: fdn.Fig

  RenderList* = ref object
    inner: fdn.RenderList

  Renders* = ref object
    inner: fdn.Renders

proc newFig(): Fig =
  Fig(inner: fdn.Fig(kind: fdn.nkFrame))

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

when ExportSiwinShim:
  proc siwinBackendNameBinding(): string =
    siwinBackendName()

  proc siwinWindowTitleBinding(suffix: string): string =
    siwinWindowTitle(suffix = suffix)

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

proc zLevel(fig: Fig): ZLevel =
  fig.inner.zlevel.int8

proc setZLevel(fig: Fig, zLevel: ZLevel) =
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

proc setRotation(fig: Fig, rotation: float32) =
  fig.inner.rotation = rotation

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

proc containsLayer(renders: Renders, zLevel: ZLevel): bool =
  renders.inner.contains(fdn.ZLevel(zLevel))

proc addRoot(renders: Renders, zLevel: ZLevel, root: Fig): int16 =
  try:
    renders.inner.addRoot(fdn.ZLevel(zLevel), root.inner).int16
  except CatchableError:
    -1'i16

proc addChild(renders: Renders, zLevel: ZLevel, parentIdx: int16, child: Fig): int16 =
  try:
    renders.inner.addChild(
      fdn.ZLevel(zLevel),
      fdn.FigIdx(parentIdx),
      child.inner,
    ).int16
  except CatchableError:
    -1'i16

proc layerNodeCount(renders: Renders, zLevel: ZLevel): int =
  try:
    if not renders.containsLayer(zLevel):
      return 0
    renders.inner[fdn.ZLevel(zLevel)].nodes.len
  except CatchableError:
    0

proc layerRootCount(renders: Renders, zLevel: ZLevel): int =
  try:
    if not renders.containsLayer(zLevel):
      return 0
    renders.inner[fdn.ZLevel(zLevel)].rootIds.len
  except CatchableError:
    0

proc getLayerNode(renders: Renders, zLevel: ZLevel, nodeIdx: int16): Fig =
  try:
    Fig(inner: renders.inner[fdn.ZLevel(zLevel)].nodes[nodeIdx.int])
  except CatchableError:
    newFig()

exportEnums:
  FigKind

exportRefObject Fig:
  constructor:
    newFig()
  procs:
    copy(Fig)
    kind(Fig)
    setKind(Fig, FigKind)
    zLevel(Fig)
    setZLevel(Fig, ZLevel)
    x(Fig)
    y(Fig)
    width(Fig)
    height(Fig)
    setScreenBox(Fig, float32, float32, float32, float32)
    setFillColor(Fig, uint8, uint8, uint8, uint8)
    setRotation(Fig, float32)

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
    containsLayer(Renders, ZLevel)
    addRoot(Renders, ZLevel, Fig)
    addChild(Renders, ZLevel, int16, Fig)
    layerNodeCount(Renders, ZLevel)
    layerRootCount(Renders, ZLevel)
    getLayerNode(Renders, ZLevel, int16)

exportProcs:
  newRectangleFig
  newTextFig
  newImageFig
  newTransformFig
  figDataDir
  setFigDataDir
  figUiScale
  setFigUiScale
  scaled(float32)
  descaled(float32)

when ExportSiwinShim:
  exportProcs:
    siwinBackendNameBinding
    siwinWindowTitleBinding

writeFiles("bindings/generated", "FigDraw")

include generated/internal
