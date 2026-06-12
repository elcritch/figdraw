import std/[hashes, math, tables]
export tables

from pkg/pixie import Image
import pkg/chroma

import ./commons
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

method kind*(impl: BackendContext): RendererBackendKind {.base.} =
  raise newException(ValueError, "Backend kind unavailable")

method entriesPtr*(impl: BackendContext): ptr Table[Hash, Rect] {.base.} =
  raise newException(ValueError, "Backend entries unavailable")

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
