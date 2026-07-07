import std/[hashes, locks, math, sets, tables]
export tables

from pkg/pixie import Image
import pkg/chroma

import ./commons
import ./common/fonttypes
import ./figbasics
import ./fignodes

when UseMetalBackend:
  import metalx/[cametal, metal]

type RendererBackendKind* {.pure.} = enum
  rbOpenGL
  rbMetal
  rbVulkan

proc backendName*(kind: RendererBackendKind): string =
  case kind
  of rbMetal: "Metal"
  of rbVulkan: "Vulkan"
  of rbOpenGL: "OpenGL"

when UseMetalBackend:
  const PreferredBackendKind* = rbMetal
elif UseVulkanBackend:
  const PreferredBackendKind* = rbVulkan
else:
  const PreferredBackendKind* = rbOpenGL

type SdfMode* {.pure.} = enum
  sdfModeAtlas = 0
  sdfModeClipAA = 3
  sdfModeDropShadow = 7
  sdfModeDropShadowAA = 8
  sdfModeInsetShadow = 9
  sdfModeInsetShadowAnnular = 10
  sdfModeAnnular = 11
  sdfModeAnnularAA = 12
  sdfModeMsdf = 13
  sdfModeMtsdf = 14
  sdfModeMsdfAnnular = 15
  sdfModeMtsdfAnnular = 16
  sdfModeBackdropBlur = 17

type
  AtlasEntryKind* = enum
    aekImage
    aekGlyph
    aekGenerated

  AtlasEntryMeta* = object
    kind*: AtlasEntryKind
    imageId*: ImageId
    fontId*: FontId
    typefaceId*: TypefaceId

  AtlasUsage* = object
    ## Snapshot of atlas occupancy.
    ##
    ## `usedArea` is the sum of live atlas entries. `packedArea` is the atlas
    ## packer's skyline/high-water estimate and can include margins and holes,
    ## so it is the better signal for deciding when to reset the atlas.
    snapshotId*: uint64
    atlasSize*: int
    atlasArea*: int
    usedArea*: int
    packedArea*: int
    entryCount*: int
    imageCount*: int
    glyphCount*: int
    generatedCount*: int
    unknownCount*: int

  BackendFillKind* = enum
    bfColor
    bfLinear2
    bfLinear3

  BackendFill* = object
    case kind*: BackendFillKind
    of bfColor:
      color*: ColorRGBA
    of bfLinear2:
      lin2Axis*: FillGradientAxis
      lin2Start*, lin2Stop*: ColorRGBA
    of bfLinear3:
      lin3Axis*: FillGradientAxis
      lin3Start*, lin3Mid*, lin3Stop*: ColorRGBA
      lin3MidPos*: float32

func toBackendFill*(fill: Fill): BackendFill =
  case fill.kind
  of flColor:
    BackendFill(kind: bfColor, color: fill.color)
  of flLinear2:
    BackendFill(
      kind: bfLinear2,
      lin2Axis: fill.lin2.axis,
      lin2Start: fill.lin2.start,
      lin2Stop: fill.lin2.stop,
    )
  of flLinear3:
    BackendFill(
      kind: bfLinear3,
      lin3Axis: fill.lin3.axis,
      lin3Start: fill.lin3.start,
      lin3Mid: fill.lin3.mid,
      lin3Stop: fill.lin3.stop,
      lin3MidPos: clamp(fill.lin3.midPos.float32 / 255.0'f32, 0.01'f32, 0.99'f32),
    )

func lerpColor(a, b: ColorRGBA, t: float32): ColorRGBA =
  let
    clampedT = clamp(t, 0.0'f32, 1.0'f32)
    invT = 1.0'f32 - clampedT
  result.r = (a.r.float32 * invT + b.r.float32 * clampedT).round().uint8
  result.g = (a.g.float32 * invT + b.g.float32 * clampedT).round().uint8
  result.b = (a.b.float32 * invT + b.b.float32 * clampedT).round().uint8
  result.a = (a.a.float32 * invT + b.a.float32 * clampedT).round().uint8

func sampleColor*(fill: BackendFill, t: float32): ColorRGBA =
  case fill.kind
  of bfColor:
    fill.color
  of bfLinear2:
    lerpColor(fill.lin2Start, fill.lin2Stop, t)
  of bfLinear3:
    let clampedT = clamp(t, 0.0'f32, 1.0'f32)
    if clampedT <= fill.lin3MidPos:
      lerpColor(fill.lin3Start, fill.lin3Mid, clampedT / fill.lin3MidPos)
    else:
      lerpColor(
        fill.lin3Mid,
        fill.lin3Stop,
        (clampedT - fill.lin3MidPos) / (1.0'f32 - fill.lin3MidPos),
      )

func fillGradientAxis(fill: BackendFill): FillGradientAxis =
  case fill.kind
  of bfColor: fgaX
  of bfLinear2: fill.lin2Axis
  of bfLinear3: fill.lin3Axis

func gradientColors*(fill: BackendFill): array[4, ColorRGBA] =
  ## Vertex order: 0=BL, 1=BR, 2=TR, 3=TL
  case fill.fillGradientAxis()
  of fgaX:
    result[0] = fill.sampleColor(0.0'f32)
    result[1] = fill.sampleColor(1.0'f32)
    result[2] = fill.sampleColor(1.0'f32)
    result[3] = fill.sampleColor(0.0'f32)
  of fgaY:
    result[0] = fill.sampleColor(1.0'f32)
    result[1] = fill.sampleColor(1.0'f32)
    result[2] = fill.sampleColor(0.0'f32)
    result[3] = fill.sampleColor(0.0'f32)
  of fgaDiagTLBR:
    result[0] = fill.sampleColor(0.5'f32)
    result[1] = fill.sampleColor(1.0'f32)
    result[2] = fill.sampleColor(0.5'f32)
    result[3] = fill.sampleColor(0.0'f32)
  of fgaDiagBLTR:
    result[0] = fill.sampleColor(0.0'f32)
    result[1] = fill.sampleColor(0.5'f32)
    result[2] = fill.sampleColor(1.0'f32)
    result[3] = fill.sampleColor(0.5'f32)

type BackendContext* = ref object of RootObj
  imageOwners: Table[ImageId, HashSet[OwnerToken]]
  fontOwners: Table[FontId, HashSet[OwnerToken]]

var
  atlasUsageLock: Lock
  lastAtlasUsage: AtlasUsage
  nextAtlasUsageSnapshotId: uint64

atlasUsageLock.initLock()

func usedRatio*(usage: AtlasUsage): float32 =
  if usage.atlasArea <= 0:
    0.0'f32
  else:
    usage.usedArea.float32 / usage.atlasArea.float32

func packedRatio*(usage: AtlasUsage): float32 =
  if usage.atlasArea <= 0:
    0.0'f32
  else:
    usage.packedArea.float32 / usage.atlasArea.float32

method kind*(impl: BackendContext): RendererBackendKind {.base.} =
  raise newException(ValueError, "Backend kind unavailable")

method entriesPtr*(impl: BackendContext): ptr Table[Hash, Rect] {.base.} =
  raise newException(ValueError, "Backend entries unavailable")

method atlasEntryMetaPtr*(
    impl: BackendContext
): var Table[Hash, AtlasEntryMeta] {.base.} =
  raise newException(ValueError, "Backend atlas metadata unavailable")

method atlasSize*(impl: BackendContext): int {.base.} =
  raise newException(ValueError, "Backend atlas size unavailable")

method atlasPackedArea*(impl: BackendContext): int {.base.} =
  ## Approximate area consumed by the atlas packer, including holes/margins.
  0

method pixelScale*(impl: BackendContext): float32 {.base.} =
  raise newException(ValueError, "Backend pixelScale unavailable")

method hasImage*(impl: BackendContext, key: Hash): bool {.base.} =
  raise newException(ValueError, "Backend hasImage unavailable")

method addImage*(impl: BackendContext, key: Hash, image: Image) {.base.} =
  raise newException(ValueError, "Backend addImage unavailable")

method putImage*(impl: BackendContext, path: Hash, image: Image) {.base.} =
  raise newException(ValueError, "Backend putImage unavailable")

method updateImage*(impl: BackendContext, path: Hash, image: Image) {.base.} =
  raise newException(ValueError, "Backend updateImage unavailable")

method putImage*(impl: BackendContext, imgObj: ImgObj) {.base.} =
  raise newException(ValueError, "Backend putImage unavailable")

func entryArea(rect: Rect, atlasSize: int): int =
  if atlasSize <= 0:
    return 0
  let
    w = max(0, round(rect.w * atlasSize.float32).int)
    h = max(0, round(rect.h * atlasSize.float32).int)
  w * h

proc atlasUsage*(impl: BackendContext): AtlasUsage =
  ## Computes exact live entry counts from the backend atlas tables.
  ##
  ## Call this from the render/backend thread. For cross-thread monitoring, use
  ## `atlasUsageSnapshot`, which returns the last value published by rendering.
  result.atlasSize = max(0, impl.atlasSize())
  result.atlasArea = result.atlasSize * result.atlasSize
  result.entryCount = impl.entriesPtr()[].len

  for key, rect in impl.entriesPtr()[].pairs:
    result.usedArea += entryArea(rect, result.atlasSize)
    if key in impl.atlasEntryMetaPtr():
      case impl.atlasEntryMetaPtr()[key].kind
      of aekImage:
        inc result.imageCount
      of aekGlyph:
        inc result.glyphCount
      of aekGenerated:
        inc result.generatedCount
    else:
      inc result.unknownCount

  result.packedArea = impl.atlasPackedArea()
  if result.packedArea < result.usedArea:
    result.packedArea = result.usedArea
  if result.atlasArea > 0:
    result.usedArea = min(result.usedArea, result.atlasArea)
    result.packedArea = min(result.packedArea, result.atlasArea)

proc publishAtlasUsage*(impl: BackendContext) =
  ## Render-thread helper that publishes a cheap cross-thread atlas snapshot.
  var usage = impl.atlasUsage()
  withLock atlasUsageLock:
    inc nextAtlasUsageSnapshotId
    usage.snapshotId = nextAtlasUsageSnapshotId
    lastAtlasUsage = usage

proc atlasUsageSnapshot*(): AtlasUsage =
  ## Returns the last atlas usage snapshot published by rendering.
  ##
  ## This is cheap and cross-thread safe. It may be stale until the render
  ## thread processes cache messages and publishes another frame.
  withLock atlasUsageLock:
    result = lastAtlasUsage

proc removeAtlasEntry*(impl: BackendContext, key: Hash) =
  impl.entriesPtr()[].del(key)
  impl.atlasEntryMetaPtr().del(key)

proc markImageEntry*(impl: BackendContext, id: ImageId) =
  impl.atlasEntryMetaPtr()[id.Hash] = AtlasEntryMeta(kind: aekImage, imageId: id)

proc markGlyphEntry*(
    impl: BackendContext, key: Hash, fontId: FontId, typefaceId: TypefaceId
) =
  impl.atlasEntryMetaPtr()[key] =
    AtlasEntryMeta(kind: aekGlyph, fontId: fontId, typefaceId: typefaceId)

proc markGeneratedEntry*(impl: BackendContext, key: Hash) =
  impl.atlasEntryMetaPtr()[key] = AtlasEntryMeta(kind: aekGenerated)

method removeImage*(impl: BackendContext, id: ImageId) {.base.} =
  let key = id.Hash
  if key in impl.atlasEntryMetaPtr():
    let meta = impl.atlasEntryMetaPtr()[key]
    if meta.kind == aekImage and meta.imageId == id:
      impl.removeAtlasEntry(key)
  else:
    impl.entriesPtr()[].del(key)

method clearImageAtlas*(impl: BackendContext) {.base.} =
  impl.entriesPtr()[].clear()
  impl.atlasEntryMetaPtr().clear()

method clearFontGlyphs*(impl: BackendContext, fontId: FontId) {.base.} =
  var keys: seq[Hash]
  for key, meta in impl.atlasEntryMetaPtr().pairs:
    if meta.kind == aekGlyph and meta.fontId == fontId:
      keys.add(key)
  for key in keys:
    impl.removeAtlasEntry(key)

method clearTypefaceGlyphs*(impl: BackendContext, typefaceId: TypefaceId) {.base.} =
  var keys: seq[Hash]
  for key, meta in impl.atlasEntryMetaPtr().pairs:
    if meta.kind == aekGlyph and meta.typefaceId == typefaceId:
      keys.add(key)
  for key in keys:
    impl.removeAtlasEntry(key)

proc retainImageOwner*(impl: BackendContext, id: ImageId, ownerToken: OwnerToken) =
  var owners = impl.imageOwners.getOrDefault(id, initHashSet[OwnerToken]())
  owners.incl(ownerToken)
  impl.imageOwners[id] = owners

proc releaseImageOwner*(
    impl: BackendContext, id: ImageId, ownerToken: OwnerToken
): bool =
  if id in impl.imageOwners:
    var owners = impl.imageOwners[id]
    owners.excl(ownerToken)
    if owners.len == 0:
      impl.imageOwners.del(id)
      result = true
    else:
      impl.imageOwners[id] = owners

proc retainFontOwner*(impl: BackendContext, fontId: FontId, ownerToken: OwnerToken) =
  var owners = impl.fontOwners.getOrDefault(fontId, initHashSet[OwnerToken]())
  owners.incl(ownerToken)
  impl.fontOwners[fontId] = owners

proc releaseFontOwner*(
    impl: BackendContext, fontId: FontId, ownerToken: OwnerToken
): bool =
  if fontId in impl.fontOwners:
    var owners = impl.fontOwners[fontId]
    owners.excl(ownerToken)
    if owners.len == 0:
      impl.fontOwners.del(fontId)
      result = true
    else:
      impl.fontOwners[fontId] = owners

method drawImage*(
    impl: BackendContext,
    path: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) {.base.} =
  raise newException(ValueError, "Backend drawImage unavailable")

proc drawImage*(
    impl: BackendContext,
    path: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    flipY: bool,
) =
  impl.drawImage(path, pos, colors, vec2(0, 0), flipY)

proc drawImage*(
    impl: BackendContext, path: Hash, pos: Vec2, color: Color, flipY: bool
) =
  let solid = color.rgba()
  impl.drawImage(path, pos, [solid, solid, solid, solid], vec2(0, 0), flipY)

proc drawImage*(
    impl: BackendContext, path: Hash, pos: Vec2, color: Color, size: Vec2, flipY: bool
) =
  let solid = color.rgba()
  impl.drawImage(path, pos, [solid, solid, solid, solid], size, flipY)

method drawImageAdj*(
    impl: BackendContext, path: Hash, pos: Vec2, color: Color, size: Vec2
) {.base.} =
  raise newException(ValueError, "Backend drawImageAdj unavailable")

method drawRect*(impl: BackendContext, rect: Rect, color: Color) {.base.} =
  raise newException(ValueError, "Backend drawRect unavailable")

method drawRoundedRectSdf*(
    impl: BackendContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: array[DirectionCorners, float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) {.base.} =
  raise newException(ValueError, "Backend drawRoundedRectSdf unavailable")

method drawRoundedRectSdf*(
    impl: BackendContext,
    rect: Rect,
    fill: BackendFill,
    radii: array[DirectionCorners, float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) {.base.} =
  impl.drawRoundedRectSdf(
    rect = rect,
    colors = fill.gradientColors(),
    radii = radii,
    mode = mode,
    factor = factor,
    spread = spread,
    shapeSize = shapeSize,
  )

method drawRoundedRectSdf*(
    impl: BackendContext,
    rect: Rect,
    color: Color,
    radii: array[DirectionCorners, float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) {.base.} =
  let solid = color.rgba()
  impl.drawRoundedRectSdf(
    rect = rect,
    colors = [solid, solid, solid, solid],
    radii = radii,
    mode = mode,
    factor = factor,
    spread = spread,
    shapeSize = shapeSize,
  )

method drawMsdfImage*(
    impl: BackendContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32,
    strokeWeight: float32,
    flipY: bool = false,
) {.base.} =
  discard flipY
  raise newException(ValueError, "Backend drawMsdfImage unavailable")

method drawMtsdfImage*(
    impl: BackendContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32,
    strokeWeight: float32,
    flipY: bool = false,
) {.base.} =
  discard flipY
  raise newException(ValueError, "Backend drawMtsdfImage unavailable")

method drawBackdropBlur*(
    impl: BackendContext,
    rect: Rect,
    radii: array[DirectionCorners, float32],
    blurRadius: float32,
) {.base.} =
  raise newException(ValueError, "Backend drawBackdropBlur unavailable")

method beginMask*(
    impl: BackendContext, clipRect: Rect, radii: array[DirectionCorners, float32]
) {.base.} =
  raise newException(ValueError, "Backend beginMask unavailable")

method endMask*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend endMask unavailable")

method popMask*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend popMask unavailable")

method beginRectMask*(
    impl: BackendContext, maskRect: Rect, radii: array[DirectionCorners, float32]
) {.base.} =
  impl.beginMask(maskRect, radii)
  impl.endMask()

method popRectMask*(impl: BackendContext) {.base.} =
  impl.popMask()

method beginFrame*(
    impl: BackendContext, frameSize: Vec2, clearMain: bool, clearMainColor: Color
) {.base.} =
  raise newException(ValueError, "Backend beginFrame unavailable")

method endFrame*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend endFrame unavailable")

method translate*(impl: BackendContext, v: Vec2) {.base.} =
  raise newException(ValueError, "Backend translate unavailable")

method rotate*(impl: BackendContext, angle: float32) {.base.} =
  raise newException(ValueError, "Backend rotate unavailable")

method scale*(impl: BackendContext, s: float32) {.base.} =
  raise newException(ValueError, "Backend scale unavailable")

method scale*(impl: BackendContext, s: Vec2) {.base.} =
  raise newException(ValueError, "Backend scale unavailable")

method applyTransform*(impl: BackendContext, m: Mat4) {.base.} =
  raise newException(ValueError, "Backend applyTransform unavailable")

method saveTransform*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend saveTransform unavailable")

method restoreTransform*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend restoreTransform unavailable")

method transformMirrorsY*(impl: BackendContext): bool {.base.} =
  false

method readPixels*(impl: BackendContext, frame: Rect, readFront: bool): Image {.base.} =
  raise newException(ValueError, "Backend readPixels unavailable")

method textLcdFilteringEnabled*(impl: BackendContext): bool {.base.} =
  false

method setTextLcdFilteringEnabled*(impl: BackendContext, enabled: bool) {.base.} =
  discard

method textSubpixelPositioningEnabled*(impl: BackendContext): bool {.base.} =
  false

method setTextSubpixelPositioningEnabled*(
    impl: BackendContext, enabled: bool
) {.base.} =
  discard

method textSubpixelGlyphVariantsEnabled*(impl: BackendContext): bool {.base.} =
  false

method setTextSubpixelGlyphVariantsEnabled*(
    impl: BackendContext, enabled: bool
) {.base.} =
  discard

method setTextSubpixelShift*(impl: BackendContext, shift: float32) {.base.} =
  discard

when UseMetalBackend:
  method metalDevice*(impl: BackendContext): MTLDevice {.base.} =
    nil

  method setPresentLayer*(impl: BackendContext, layer: CAMetalLayer) {.base.} =
    discard

when UseVulkanBackend:
  method setPresentXlibTarget*(
      impl: BackendContext, display: pointer, window: uint64
  ) {.base.} =
    discard

  method setPresentWin32Target*(
      impl: BackendContext, hinstance: pointer, hwnd: pointer
  ) {.base.} =
    discard
