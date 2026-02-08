import std/[hashes, tables]
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

method drawImage*(impl: BackendContext, path: Hash, pos: Vec2, color: Color) {.base.} =
  raise newException(ValueError, "Backend drawImage unavailable")

method drawImage*(
    impl: BackendContext, path: Hash, pos: Vec2, color: Color, size: Vec2
) {.base.} =
  raise newException(ValueError, "Backend drawImage unavailable")

method drawImageAdj*(
    impl: BackendContext, path: Hash, pos: Vec2, color: Color, size: Vec2
) {.base.} =
  raise newException(ValueError, "Backend drawImageAdj unavailable")

method drawRect*(impl: BackendContext, rect: Rect, color: Color) {.base.} =
  raise newException(ValueError, "Backend drawRect unavailable")

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
  raise newException(ValueError, "Backend drawRoundedRectSdf unavailable")

method drawMsdfImage*(
    impl: BackendContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32,
    strokeWeight: float32,
) {.base.} =
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
) {.base.} =
  raise newException(ValueError, "Backend drawMtsdfImage unavailable")

method setMaskRect*(
    impl: BackendContext,
    clipRect: Rect,
    radii = array[DirectionCorners, float32]
) {.base.} =
  raise newException(ValueError, "Backend beginMask unavailable")

method beginMask*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend beginMask unavailable")

method endMask*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend endMask unavailable")

method popMask*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend popMask unavailable")

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

method saveTransform*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend saveTransform unavailable")

method restoreTransform*(impl: BackendContext) {.base.} =
  raise newException(ValueError, "Backend restoreTransform unavailable")

method readPixels*(impl: BackendContext, frame: Rect, readFront: bool): Image {.base.} =
  raise newException(ValueError, "Backend readPixels unavailable")

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
