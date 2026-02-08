import std/[hashes, strformat, tables]

import darwin/objc/runtime
import darwin/foundation/[nserror, nsstring]

import pkg/pixie
import pkg/pixie/simd
import pkg/chroma
import pkg/chronicles
import metalx/[cametal, metal]
import metalx/objc_owned

import ../commons
import ../figbackend as figbackend
import ./metal_sources
import ../common/formatflippy
import ../fignodes
import ../utils/drawextras

export drawextras

logScope:
  scope = "metal"

proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

const quadLimit = 10_921
const maxFramesInFlight = 3

type PassKind = enum
  pkNone
  pkMain
  pkMask
  pkBlit

type SdfModeData = uint16

type FlushBuffers = object
  positions: ObjcOwned[MTLBuffer]
  positionsCapacity: int
  colors: ObjcOwned[MTLBuffer]
  colorsCapacity: int
  uvs: ObjcOwned[MTLBuffer]
  uvsCapacity: int
  sdfParams: ObjcOwned[MTLBuffer]
  sdfParamsCapacity: int
  sdfRadii: ObjcOwned[MTLBuffer]
  sdfRadiiCapacity: int
  sdfModeAttr: ObjcOwned[MTLBuffer]
  sdfModeAttrCapacity: int
  sdfFactors: ObjcOwned[MTLBuffer]
  sdfFactorsCapacity: int

type FrameArena = object
  flushBuffers: seq[FlushBuffers]
  flushBufferCursor: int
  inUse: bool

type InFlightFrame = object
  commandBuffer: ObjcOwned[MTLCommandBuffer]
  arenaIndex: int

type MetalContext* = ref object of figbackend.BackendContext # Metal objects
  device: ObjcOwned[MTLDevice]
  queue: ObjcOwned[MTLCommandQueue]
  commandBuffer: ObjcOwned[MTLCommandBuffer]
  encoder: MTLRenderCommandEncoder
  passKind: PassKind

  pipelineMain: ObjcOwned[MTLRenderPipelineState]
  pipelineMask: ObjcOwned[MTLRenderPipelineState]
  pipelineBlit: ObjcOwned[MTLRenderPipelineState]

  # Optional presentation target.
  # Windowing code owns attaching/sizing this layer.
  presentLayer*: CAMetalLayer

  # Render targets
  offscreenTexture: ObjcOwned[MTLTexture]
  atlasTexture: ObjcOwned[MTLTexture]
  maskTextures: seq[ObjcOwned[MTLTexture]]
  maskTextureWrite: int ## Index of active mask stack (0 means no mask).

  atlasSize: int
  atlasMargin: int
  quadCount: int
  maxQuads: int
  mat*: Mat4
  mats: seq[Mat4]
  entries*: Table[Hash, Rect]
  heights: seq[uint16]
  proj*: Mat4
  frameSize: Vec2
  frameBegun, maskBegun: bool
  pixelate*: bool
  pixelScale*: float32

  # Buffer data mirrored on CPU and uploaded each flush.
  indices: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[uint16]]
  positions: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[float32]]
  colors: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[uint8]]
  uvs: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[float32]]
  sdfParams: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[float32]]
  sdfRadii: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[float32]]
  sdfModeAttr: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[SdfModeData]]
  sdfFactors: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[float32]]

  # SDF shader uniform (global)
  aaFactor: float32

  # For screenshot readback.
  lastCommitted: ObjcOwned[MTLCommandBuffer]
  frameArenas: seq[FrameArena]
  activeArena: int
  inFlightFrames: seq[InFlightFrame]

  # Drains per-frame autoreleased Metal/Foundation objects (render pass descriptors,
  # temporary NSStrings, etc). Without an autorelease pool, these accumulate and look
  # like a per-frame leak in long-running apps.
  frameAutoreleasePool: AutoreleasePool

proc flush(ctx: MetalContext, maskTextureRead: int = ctx.maskTextureWrite)

proc ensureDeviceAndPipelines(ctx: MetalContext)

method metalDevice*(ctx: MetalContext): MTLDevice =
  ## Exposes the MTLDevice for windowing code that needs to create a CAMetalLayer.
  if ctx.device.isNil:
    ctx.ensureDeviceAndPipelines()
  result = ctx.device.borrow

proc toKey*(h: Hash): Hash =
  h

method hasImage*(ctx: MetalContext, key: Hash): bool =
  key in ctx.entries

proc tryGetImageRect(ctx: MetalContext, imageId: Hash, rect: var Rect): bool

proc mtlRegion2D(x, y, w, h: int): MTLRegion =
  result.origin = MTLOrigin(x: NSUInteger(x), y: NSUInteger(y), z: 0)
  result.size = MTLSize(width: NSUInteger(w), height: NSUInteger(h), depth: 1)

proc newTexture2D(
    ctx: MetalContext,
    pixelFormat: MTLPixelFormat,
    width, height: int,
    usage: MTLTextureUsage,
    storageMode = MTLStorageModeShared,
    mipmapped = false,
): MTLTexture =
  let desc = MTLTextureDescriptor.texture2DDescriptorWithPixelFormat(
    pixelFormat, NSUInteger(width), NSUInteger(height), mipmapped
  )
  desc.setUsage(usage)
  desc.setStorageMode(storageMode)
  result = ctx.device.borrow.newTextureWithDescriptor(desc)

proc updateSubImage(ctx: MetalContext, texture: MTLTexture, x, y: int, image: Image) =
  # Pixie Image is RGBA; our atlas is RGBA8.
  let region = mtlRegion2D(x, y, image.width, image.height)
  texture.replaceRegion(region, 0, image.data[0].addr, NSUInteger(image.width * 4))

proc createAtlasTexture(ctx: MetalContext, size: int): MTLTexture =
  # No mipmaps for now; keep it simple and deterministic.
  result = ctx.newTexture2D(
    pixelFormat = MTLPixelFormatRGBA8Unorm,
    width = size,
    height = size,
    usage = MTLTextureUsageShaderRead,
  )

proc createMaskTexture(ctx: MetalContext, width, height: int): MTLTexture =
  result = ctx.newTexture2D(
    pixelFormat = MTLPixelFormatR8Unorm,
    width = width,
    height = height,
    usage = MTLTextureUsage(
      cast[NSUInteger](MTLTextureUsageShaderRead) or
        cast[NSUInteger](MTLTextureUsageRenderTarget)
    ),
  )

proc ensureMask0(ctx: MetalContext) =
  if ctx.maskTextures.len > 0:
    return
  var tex = fromRetained(ctx.createMaskTexture(1, 1))
  var white = 255'u8
  tex.borrow.replaceRegion(mtlRegion2D(0, 0, 1, 1), 0, addr white, 1)
  ctx.maskTextures.add(tex)

proc ensureOffscreen(ctx: MetalContext, frameSize: Vec2) =
  let w = max(1, frameSize.x.int)
  let h = max(1, frameSize.y.int)
  if not ctx.offscreenTexture.isNil:
    # If size matches, keep existing.
    if ctx.offscreenTexture.borrow.width.int == w and
        ctx.offscreenTexture.borrow.height.int == h:
      return
  ctx.offscreenTexture.resetRetained(
    ctx.newTexture2D(
      pixelFormat = MTLPixelFormatBGRA8Unorm,
      width = w,
      height = h,
      usage = MTLTextureUsage(
        cast[NSUInteger](MTLTextureUsageShaderRead) or
          cast[NSUInteger](MTLTextureUsageRenderTarget)
      ),
    )
  )

proc endEncoder(ctx: MetalContext) =
  if not ctx.encoder.isNil:
    endEncoding(ctx.encoder)
    ctx.encoder = nil
    ctx.passKind = pkNone

proc beginPass(
    ctx: MetalContext,
    kind: PassKind,
    target: MTLTexture,
    clear: bool,
    clearColor: MTLClearColor,
) =
  ctx.endEncoder()
  let pass = MTLRenderPassDescriptor.renderPassDescriptor()
  let att0 = objectAtIndexedSubscript(colorAttachments(pass), 0)
  setTexture(att0, target)
  setStoreAction(att0, MTLStoreActionStore)
  if clear:
    setLoadAction(att0, MTLLoadActionClear)
    setClearColor(att0, clearColor)
  else:
    setLoadAction(att0, MTLLoadActionLoad)
  ctx.encoder = renderCommandEncoderWithDescriptor(ctx.commandBuffer.borrow, pass)
  ctx.passKind = kind

proc ensureMainPass(ctx: MetalContext, clear: bool, clearColor: MTLClearColor) =
  if ctx.passKind == pkMain and not ctx.encoder.isNil:
    return
  ctx.beginPass(pkMain, ctx.offscreenTexture.borrow, clear, clearColor)

proc ensureMaskPass(ctx: MetalContext, clear: bool, clearColor: MTLClearColor) =
  if ctx.passKind == pkMask and not ctx.encoder.isNil:
    return
  ctx.beginPass(
    pkMask, ctx.maskTextures[ctx.maskTextureWrite].borrow, clear, clearColor
  )

proc ensureDeviceAndPipelines(ctx: MetalContext) =
  if not ctx.device.isNil and not ctx.queue.isNil and not ctx.pipelineMain.isNil and
      not ctx.pipelineMask.isNil and not ctx.pipelineBlit.isNil:
    return

  withAutoreleasePool:
    let dev = MTLCreateSystemDefaultDevice()
    if dev.isNil:
      raise newException(ValueError, "Metal device not available")
    ctx.device.resetRetained(dev)

    let q = newCommandQueue(ctx.device.borrow)
    if q.isNil:
      raise newException(ValueError, "Failed to create Metal command queue")
    ctx.queue.resetRetained(q)

    let shaderSource = metalShaderSource

    var err: NSError
    let library = fromRetained(
      newLibraryWithSource(
        ctx.device.borrow,
        NSString.withUTF8String(cstring(shaderSource)),
        MTLCompileOptions(nil),
        addr err,
      )
    )
    if library.isNil:
      if not err.isNil:
        error "Failed to compile Metal shaders", error = $err
      raise newException(ValueError, "Failed to compile Metal shaders")

    let vsMain = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("vs_main")))
    )
    let fsMain = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("fs_main")))
    )
    let fsMask = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("fs_mask")))
    )
    let vsBlit = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("vs_blit")))
    )
    let fsBlit = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("fs_blit")))
    )
    if vsMain.isNil or fsMain.isNil or fsMask.isNil or vsBlit.isNil or fsBlit.isNil:
      raise newException(ValueError, "Failed to find Metal shader functions")

    proc configureBlend(att: MTLRenderPipelineColorAttachmentDescriptor) =
      setBlendingEnabled(att, true)
      setSourceRGBBlendFactor(att, MTLBlendFactorSourceAlpha)
      setDestinationRGBBlendFactor(att, MTLBlendFactorOneMinusSourceAlpha)
      setRgbBlendOperation(att, MTLBlendOperationAdd)
      setSourceAlphaBlendFactor(att, MTLBlendFactorOne)
      setDestinationAlphaBlendFactor(att, MTLBlendFactorOneMinusSourceAlpha)
      setAlphaBlendOperation(att, MTLBlendOperationAdd)

    # Main pipeline (offscreen BGRA8).
    block:
      let pd = fromRetained(MTLRenderPipelineDescriptor.alloc().init())
      setVertexFunction(pd.borrow, vsMain.borrow)
      setFragmentFunction(pd.borrow, fsMain.borrow)
      let ca0 = objectAtIndexedSubscript(colorAttachments(pd.borrow), 0)
      setPixelFormat(ca0, MTLPixelFormatBGRA8Unorm)
      configureBlend(ca0)
      ctx.pipelineMain.resetRetained(
        newRenderPipelineStateWithDescriptor(ctx.device.borrow, pd.borrow, addr err)
      )
      if ctx.pipelineMain.isNil:
        if not err.isNil:
          error "Failed to create Metal main pipeline", error = $err
        raise newException(ValueError, "Failed to create Metal main pipeline")

    # Mask pipeline (R8).
    block:
      let pd = fromRetained(MTLRenderPipelineDescriptor.alloc().init())
      setVertexFunction(pd.borrow, vsMain.borrow)
      setFragmentFunction(pd.borrow, fsMask.borrow)
      let ca0 = objectAtIndexedSubscript(colorAttachments(pd.borrow), 0)
      setPixelFormat(ca0, MTLPixelFormatR8Unorm)
      configureBlend(ca0)
      ctx.pipelineMask.resetRetained(
        newRenderPipelineStateWithDescriptor(ctx.device.borrow, pd.borrow, addr err)
      )
      if ctx.pipelineMask.isNil:
        if not err.isNil:
          error "Failed to create Metal mask pipeline", error = $err
        raise newException(ValueError, "Failed to create Metal mask pipeline")

    # Blit pipeline (drawable BGRA8, no blending).
    block:
      let pd = fromRetained(MTLRenderPipelineDescriptor.alloc().init())
      setVertexFunction(pd.borrow, vsBlit.borrow)
      setFragmentFunction(pd.borrow, fsBlit.borrow)
      let ca0 = objectAtIndexedSubscript(colorAttachments(pd.borrow), 0)
      setPixelFormat(ca0, MTLPixelFormatBGRA8Unorm)
      ctx.pipelineBlit.resetRetained(
        newRenderPipelineStateWithDescriptor(ctx.device.borrow, pd.borrow, addr err)
      )
      if ctx.pipelineBlit.isNil:
        if not err.isNil:
          error "Failed to create Metal blit pipeline", error = $err
        raise newException(ValueError, "Failed to create Metal blit pipeline")

proc upload(ctx: MetalContext) =
  let vertexCount = ctx.quadCount * 4
  if vertexCount <= 0:
    return

  copyToBuf(
    ctx.positions.buffer.borrow, ctx.positions.data, vertexCount * 2 * sizeof(float32)
  )
  copyToBuf(ctx.uvs.buffer.borrow, ctx.uvs.data, vertexCount * 2 * sizeof(float32))
  copyToBuf(ctx.colors.buffer.borrow, ctx.colors.data, vertexCount * 4 * sizeof(uint8))
  copyToBuf(
    ctx.sdfParams.buffer.borrow, ctx.sdfParams.data, vertexCount * 4 * sizeof(float32)
  )
  copyToBuf(
    ctx.sdfRadii.buffer.borrow, ctx.sdfRadii.data, vertexCount * 4 * sizeof(float32)
  )
  copyToBuf(
    ctx.sdfModeAttr.buffer.borrow,
    ctx.sdfModeAttr.data,
    vertexCount * sizeof(SdfModeData),
  )
  copyToBuf(
    ctx.sdfFactors.buffer.borrow, ctx.sdfFactors.data, vertexCount * 2 * sizeof(float32)
  )

proc grow(ctx: MetalContext) =
  ctx.flush()
  ctx.atlasSize = ctx.atlasSize * 2
  info "grow atlasSize ", atlasSize = ctx.atlasSize
  ctx.heights.setLen(ctx.atlasSize)
  ctx.atlasTexture.resetRetained(ctx.createAtlasTexture(ctx.atlasSize))
  ctx.entries.clear()

proc findEmptyRect(ctx: MetalContext, width, height: int): Rect =
  var imgWidth = width + ctx.atlasMargin * 2
  var imgHeight = height + ctx.atlasMargin * 2

  var lowest = ctx.atlasSize
  var at = 0
  for i in 0 .. ctx.atlasSize - 1:
    var v = int(ctx.heights[i])
    if v < lowest:
      var fit = true
      for j in 0 .. imgWidth:
        if i + j >= ctx.atlasSize:
          fit = false
          break
        if int(ctx.heights[i + j]) > v:
          fit = false
          break
      if fit:
        lowest = v
        at = i

  if lowest + imgHeight > ctx.atlasSize:
    ctx.grow()
    return ctx.findEmptyRect(width, height)

  for j in at .. at + imgWidth - 1:
    ctx.heights[j] = uint16(lowest + imgHeight + ctx.atlasMargin * 2)

  rect(
    float32(at + ctx.atlasMargin),
    float32(lowest + ctx.atlasMargin),
    float32(width),
    float32(height),
  )

method putImage*(ctx: MetalContext, path: Hash, image: Image) =
  let rect = ctx.findEmptyRect(image.width, image.height)
  ctx.entries[path] = rect / float(ctx.atlasSize)
  ctx.updateSubImage(ctx.atlasTexture.borrow, int(rect.x), int(rect.y), image)

method addImage*(ctx: MetalContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method updateImage*(ctx: MetalContext, path: Hash, image: Image) =
  let rect = ctx.entries[path]
  assert rect.w == image.width.float / float(ctx.atlasSize)
  assert rect.h == image.height.float / float(ctx.atlasSize)
  ctx.updateSubImage(
    ctx.atlasTexture.borrow,
    int(rect.x * ctx.atlasSize.float),
    int(rect.y * ctx.atlasSize.float),
    image,
  )

proc logFlippy(flippy: Flippy, file: string) =
  debug "putFlippy file",
    fwidth = $flippy.width, fheight = $flippy.height, flippyPath = file

proc putFlippy*(ctx: MetalContext, path: Hash, flippy: Flippy) =
  # Metal backend currently uploads only mip 0.
  logFlippy(flippy, $path)
  if flippy.mipmaps.len == 0:
    return
  let mip0 = flippy.mipmaps[0]
  ctx.putImage(path, mip0)

method putImage*(ctx: MetalContext, imgObj: ImgObj) =
  case imgObj.kind
  of FlippyImg:
    ctx.putFlippy(imgObj.id.Hash, imgObj.flippy)
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)

proc checkBatch(ctx: MetalContext) =
  if ctx.quadCount == ctx.maxQuads:
    if ctx.maskBegun:
      ctx.flush(ctx.maskTextureWrite - 1)
    else:
      ctx.flush()

proc setVert2(buf: var seq[float32], i: int, v: Vec2) =
  buf[i * 2 + 0] = v.x
  buf[i * 2 + 1] = v.y

proc setVert4(buf: var seq[float32], i: int, v: Vec4) =
  buf[i * 4 + 0] = v.x
  buf[i * 4 + 1] = v.y
  buf[i * 4 + 2] = v.z
  buf[i * 4 + 3] = v.w

proc setVertColor(buf: var seq[uint8], i: int, color: ColorRGBA) =
  buf[i * 4 + 0] = color.r
  buf[i * 4 + 1] = color.g
  buf[i * 4 + 2] = color.b
  buf[i * 4 + 3] = color.a

func `*`*(m: Mat4, v: Vec2): Vec2 =
  (m * vec3(v.x, v.y, 0.0)).xy

proc drawQuad*(
    ctx: MetalContext,
    verts: array[4, Vec2],
    uvs: array[4, Vec2],
    colors: array[4, ColorRGBA],
) =
  ctx.checkBatch()

  let zero4 = vec4(0.0'f32)
  let offset = ctx.quadCount * 4
  ctx.positions.data.setVert2(offset + 0, verts[0])
  ctx.positions.data.setVert2(offset + 1, verts[1])
  ctx.positions.data.setVert2(offset + 2, verts[2])
  ctx.positions.data.setVert2(offset + 3, verts[3])

  ctx.uvs.data.setVert2(offset + 0, uvs[0])
  ctx.uvs.data.setVert2(offset + 1, uvs[1])
  ctx.uvs.data.setVert2(offset + 2, uvs[2])
  ctx.uvs.data.setVert2(offset + 3, uvs[3])

  ctx.colors.data.setVertColor(offset + 0, colors[0])
  ctx.colors.data.setVertColor(offset + 1, colors[1])
  ctx.colors.data.setVertColor(offset + 2, colors[2])
  ctx.colors.data.setVertColor(offset + 3, colors[3])

  ctx.sdfParams.data.setVert4(offset + 0, zero4)
  ctx.sdfParams.data.setVert4(offset + 1, zero4)
  ctx.sdfParams.data.setVert4(offset + 2, zero4)
  ctx.sdfParams.data.setVert4(offset + 3, zero4)

  ctx.sdfRadii.data.setVert4(offset + 0, zero4)
  ctx.sdfRadii.data.setVert4(offset + 1, zero4)
  ctx.sdfRadii.data.setVert4(offset + 2, zero4)
  ctx.sdfRadii.data.setVert4(offset + 3, zero4)

  let defaultFactors = vec2(0.0'f32, 0.0'f32)
  ctx.sdfFactors.data.setVert2(offset + 0, defaultFactors)
  ctx.sdfFactors.data.setVert2(offset + 1, defaultFactors)
  ctx.sdfFactors.data.setVert2(offset + 2, defaultFactors)
  ctx.sdfFactors.data.setVert2(offset + 3, defaultFactors)

  let modeVal = 0'u16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal

  inc ctx.quadCount

type SdfMode* = figbackend.SdfMode

proc drawUvRectAtlasSdf(
    ctx: MetalContext,
    at, to: Vec2,
    uvAt, uvTo: Vec2,
    color: Color,
    mode: SdfMode,
    factors: Vec2,
    params: Vec4 = vec4(0.0'f32),
) =
  ctx.checkBatch()
  assert ctx.quadCount < ctx.maxQuads

  let
    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x, uvTo.y),
      vec2(uvTo.x, uvTo.y),
      vec2(uvTo.x, uvAt.y),
      vec2(uvAt.x, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.data.setVert2(offset + 0, posQuad[0])
  ctx.positions.data.setVert2(offset + 1, posQuad[1])
  ctx.positions.data.setVert2(offset + 2, posQuad[2])
  ctx.positions.data.setVert2(offset + 3, posQuad[3])

  ctx.uvs.data.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.data.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.data.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.data.setVert2(offset + 3, uvQuad[3])

  let rgba = color.rgba()
  ctx.colors.data.setVertColor(offset + 0, rgba)
  ctx.colors.data.setVertColor(offset + 1, rgba)
  ctx.colors.data.setVertColor(offset + 2, rgba)
  ctx.colors.data.setVertColor(offset + 3, rgba)

  ctx.sdfParams.data.setVert4(offset + 0, params)
  ctx.sdfParams.data.setVert4(offset + 1, params)
  ctx.sdfParams.data.setVert4(offset + 2, params)
  ctx.sdfParams.data.setVert4(offset + 3, params)

  let zero4 = vec4(0.0'f32)
  ctx.sdfRadii.data.setVert4(offset + 0, zero4)
  ctx.sdfRadii.data.setVert4(offset + 1, zero4)
  ctx.sdfRadii.data.setVert4(offset + 2, zero4)
  ctx.sdfRadii.data.setVert4(offset + 3, zero4)

  ctx.sdfFactors.data.setVert2(offset + 0, factors)
  ctx.sdfFactors.data.setVert2(offset + 1, factors)
  ctx.sdfFactors.data.setVert2(offset + 2, factors)
  ctx.sdfFactors.data.setVert2(offset + 3, factors)

  let modeVal = mode.int.uint16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal

  inc ctx.quadCount

method drawMsdfImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMsdfAnnular else: SdfMode.sdfModeMsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = rect.xy,
    uvTo = rect.xy + rect.wh,
    color = color,
    mode = modeSel,
    factors = vec2(pxRange, sdThreshold),
    params = params,
  )

method drawMtsdfImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMtsdfAnnular else: SdfMode.sdfModeMtsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = rect.xy,
    uvTo = rect.xy + rect.wh,
    color = color,
    mode = modeSel,
    factors = vec2(pxRange, sdThreshold),
    params = params,
  )

proc setSdfGlobals*(ctx: MetalContext, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.aaFactor = aaFactor

proc drawUvRect(ctx: MetalContext, at, to: Vec2, uvAt, uvTo: Vec2, color: Color) =
  ctx.checkBatch()
  assert ctx.quadCount < ctx.maxQuads

  let
    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x, uvTo.y),
      vec2(uvTo.x, uvTo.y),
      vec2(uvTo.x, uvAt.y),
      vec2(uvAt.x, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.data.setVert2(offset + 0, posQuad[0])
  ctx.positions.data.setVert2(offset + 1, posQuad[1])
  ctx.positions.data.setVert2(offset + 2, posQuad[2])
  ctx.positions.data.setVert2(offset + 3, posQuad[3])

  ctx.uvs.data.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.data.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.data.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.data.setVert2(offset + 3, uvQuad[3])

  let rgba = color.rgba()
  ctx.colors.data.setVertColor(offset + 0, rgba)
  ctx.colors.data.setVertColor(offset + 1, rgba)
  ctx.colors.data.setVertColor(offset + 2, rgba)
  ctx.colors.data.setVertColor(offset + 3, rgba)

  let zero4 = vec4(0.0'f32)
  ctx.sdfParams.data.setVert4(offset + 0, zero4)
  ctx.sdfParams.data.setVert4(offset + 1, zero4)
  ctx.sdfParams.data.setVert4(offset + 2, zero4)
  ctx.sdfParams.data.setVert4(offset + 3, zero4)

  ctx.sdfRadii.data.setVert4(offset + 0, zero4)
  ctx.sdfRadii.data.setVert4(offset + 1, zero4)
  ctx.sdfRadii.data.setVert4(offset + 2, zero4)
  ctx.sdfRadii.data.setVert4(offset + 3, zero4)

  let defaultFactors = vec2(0.0'f32, 0.0'f32)
  ctx.sdfFactors.data.setVert2(offset + 0, defaultFactors)
  ctx.sdfFactors.data.setVert2(offset + 1, defaultFactors)
  ctx.sdfFactors.data.setVert2(offset + 2, defaultFactors)
  ctx.sdfFactors.data.setVert2(offset + 3, defaultFactors)

  let modeVal = 0'u16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal

  inc ctx.quadCount

proc drawUvRect(ctx: MetalContext, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc tryGetImageRect(ctx: MetalContext, imageId: Hash, rect: var Rect): bool =
  if imageId notin ctx.entries:
    warn "missing image in context", imageId = imageId
    return false
  rect = ctx.entries[imageId]
  true

proc drawImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale: float32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, color)

method drawImage*(ctx: MetalContext, imageId: Hash, pos: Vec2, color: Color) =
  drawImage(ctx, imageId, pos, color, 1.0'f32)

method drawImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos, pos + size, rect.xy, rect.xy + rect.wh, color)

method drawImageAdj*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let adj = vec2(2 / ctx.atlasSize.float32)
  ctx.drawUvRect(pos, pos + size, rect.xy + adj, rect.xy + rect.wh - adj, color)

proc drawSprite*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos - wh / 2, pos + wh / 2, rect.xy, rect.xy + rect.wh, color)

proc drawSprite*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos - size / 2, pos + size / 2, rect.xy, rect.xy + rect.wh, color)

method drawRect*(ctx: MetalContext, rect: Rect, color: Color) =
  const imgKey = hash("rect")
  if imgKey notin ctx.entries:
    var image = newImage(4, 4)
    image.fill(rgba(255, 255, 255, 255))
    ctx.putImage(imgKey, image)

  let uvRect = ctx.entries[imgKey]
  ctx.drawUvRect(
    rect.xy,
    rect.xy + rect.wh,
    uvRect.xy + uvRect.wh / 2,
    uvRect.xy + uvRect.wh / 2,
    color,
  )

method drawRoundedRectSdf*(
    ctx: MetalContext,
    rect: Rect,
    color: Color,
    radii: array[DirectionCorners, float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  if rect.w <= 0 or rect.h <= 0:
    return

  ctx.checkBatch()

  let
    quadHalfExtents = rect.wh * 0.5'f32
    resolvedShapeSize =
      (if shapeSize.x > 0.0'f32 and shapeSize.y > 0.0'f32: shapeSize else: rect.wh)
    shapeHalfExtents = resolvedShapeSize * 0.5'f32
    params =
      vec4(quadHalfExtents.x, quadHalfExtents.y, shapeHalfExtents.x, shapeHalfExtents.y)
    maxRadius = min(shapeHalfExtents.x, shapeHalfExtents.y)
    radiiClamped = [
      dcTopLeft: (
        if radii[dcTopLeft] <= 0.0'f32: 0.0'f32
        else: max(1.0'f32, min(radii[dcTopLeft], maxRadius)).round()
      ),
      dcTopRight: (
        if radii[dcTopRight] <= 0.0'f32: 0.0'f32
        else: max(1.0'f32, min(radii[dcTopRight], maxRadius)).round()
      ),
      dcBottomLeft: (
        if radii[dcBottomLeft] <= 0.0'f32: 0.0'f32
        else: max(1.0'f32, min(radii[dcBottomLeft], maxRadius)).round()
      ),
      dcBottomRight: (
        if radii[dcBottomRight] <= 0.0'f32: 0.0'f32
        else: max(1.0'f32, min(radii[dcBottomRight], maxRadius)).round()
      ),
    ]
    r4 = vec4(
      radiiClamped[dcTopRight],
      radiiClamped[dcBottomRight],
      radiiClamped[dcTopLeft],
      radiiClamped[dcBottomLeft],
    )

  assert ctx.quadCount < ctx.maxQuads

  let
    at = rect.xy
    to = rect.xy + rect.wh
    uvAt = vec2(0.0'f32, 0.0'f32)
    uvTo = vec2(1.0'f32, 1.0'f32)

    posQuad = [
      ceil(ctx.mat * vec2(at.x, to.y)),
      ceil(ctx.mat * vec2(to.x, to.y)),
      ceil(ctx.mat * vec2(to.x, at.y)),
      ceil(ctx.mat * vec2(at.x, at.y)),
    ]
    uvQuad = [
      vec2(uvAt.x, uvTo.y),
      vec2(uvTo.x, uvTo.y),
      vec2(uvTo.x, uvAt.y),
      vec2(uvAt.x, uvAt.y),
    ]

  let offset = ctx.quadCount * 4
  ctx.positions.data.setVert2(offset + 0, posQuad[0])
  ctx.positions.data.setVert2(offset + 1, posQuad[1])
  ctx.positions.data.setVert2(offset + 2, posQuad[2])
  ctx.positions.data.setVert2(offset + 3, posQuad[3])

  ctx.uvs.data.setVert2(offset + 0, uvQuad[0])
  ctx.uvs.data.setVert2(offset + 1, uvQuad[1])
  ctx.uvs.data.setVert2(offset + 2, uvQuad[2])
  ctx.uvs.data.setVert2(offset + 3, uvQuad[3])

  let rgba = color.rgba()
  ctx.colors.data.setVertColor(offset + 0, rgba)
  ctx.colors.data.setVertColor(offset + 1, rgba)
  ctx.colors.data.setVertColor(offset + 2, rgba)
  ctx.colors.data.setVertColor(offset + 3, rgba)

  ctx.sdfParams.data.setVert4(offset + 0, params)
  ctx.sdfParams.data.setVert4(offset + 1, params)
  ctx.sdfParams.data.setVert4(offset + 2, params)
  ctx.sdfParams.data.setVert4(offset + 3, params)

  ctx.sdfRadii.data.setVert4(offset + 0, r4)
  ctx.sdfRadii.data.setVert4(offset + 1, r4)
  ctx.sdfRadii.data.setVert4(offset + 2, r4)
  ctx.sdfRadii.data.setVert4(offset + 3, r4)

  let factors = vec2(factor, spread)
  ctx.sdfFactors.data.setVert2(offset + 0, factors)
  ctx.sdfFactors.data.setVert2(offset + 1, factors)
  ctx.sdfFactors.data.setVert2(offset + 2, factors)
  ctx.sdfFactors.data.setVert2(offset + 3, factors)

  let modeVal = mode.int.uint16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal

  inc ctx.quadCount

proc line*(ctx: MetalContext, a: Vec2, b: Vec2, weight: float32, color: Color) =
  let hash = hash((2345, a, b, (weight * 100).int, hash(color)))

  let
    w = ceil(abs(b.x - a.x)).int
    h = ceil(abs(a.y - b.y)).int
    pos = vec2(min(a.x, b.x), min(a.y, b.y))

  if w == 0 or h == 0:
    return

  if hash notin ctx.entries:
    let
      image = newImage(w, h)
      c = newContext(image)
    c.fillStyle = rgba(255, 255, 255, 255)
    c.lineWidth = weight
    c.strokeSegment(segment(a - pos, b - pos))
    ctx.putImage(hash, image)
  let uvRect = ctx.entries[hash]
  ctx.drawUvRect(
    pos, pos + vec2(w.float32, h.float32), uvRect.xy, uvRect.xy + uvRect.wh, color
  )

proc linePolygon*(ctx: MetalContext, poly: seq[Vec2], weight: float32, color: Color) =
  for i in 0 ..< poly.len:
    ctx.line(poly[i], poly[(i + 1) mod poly.len], weight, color)

method beginMask*(ctx: MetalContext) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginMask has already been called."
  # Flush any pending main-pass quads before switching into mask mode.
  ctx.flush(ctx.maskTextureWrite)
  ctx.maskBegun = true

  inc ctx.maskTextureWrite
  if ctx.maskTextureWrite >= ctx.maskTextures.len:
    ctx.maskTextures.add(
      fromRetained(ctx.createMaskTexture(ctx.frameSize.x.int, ctx.frameSize.y.int))
    )
  else:
    # Resize existing mask textures (slot 0 is the 1x1 base).
    if ctx.maskTextureWrite > 0:
      let cur = ctx.maskTextures[ctx.maskTextureWrite]
      if cur.isNil or cur.borrow.width.int != ctx.frameSize.x.int or
          cur.borrow.height.int != ctx.frameSize.y.int:
        ctx.maskTextures[ctx.maskTextureWrite].resetRetained(
          ctx.createMaskTexture(ctx.frameSize.x.int, ctx.frameSize.y.int)
        )

  ctx.ensureMaskPass(
    clear = true,
    clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
  )

method setMaskRect*(
    ctx: MetalContext,
    clipRect: Rect,
    radii: array[DirectionCorners, float32],
) =
  ctx.drawRoundedRectSdf(
    rect = clipRect,
    color = rgba(255, 0, 0, 255).color,
    radii = radii,
    mode = figbackend.SdfMode.sdfModeClipAA,
    factor = 4.0'f32,
    spread = 0.0'f32,
    shapeSize = vec2(0.0'f32, 0.0'f32),
  )

method endMask*(ctx: MetalContext) =
  assert ctx.maskBegun == true, "ctx.maskBegun has not been called."
  # Flush any remaining quads for this mask level while the mask pipeline is active.
  ctx.flush(ctx.maskTextureWrite - 1)
  ctx.maskBegun = false

  ctx.ensureMainPass(
    clear = false,
    clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
  )

method popMask*(ctx: MetalContext) =
  ctx.flush()
  dec ctx.maskTextureWrite

proc reapCompletedFrames(ctx: MetalContext) =
  if ctx.inFlightFrames.len == 0:
    return

  var write = 0
  for i in 0 ..< ctx.inFlightFrames.len:
    let frame = ctx.inFlightFrames[i]
    if not frame.commandBuffer.isNil and
        status(frame.commandBuffer.borrow) < NSUInteger(4):
      if write != i:
        ctx.inFlightFrames[write] = frame
      inc write
    else:
      if frame.arenaIndex >= 0 and frame.arenaIndex < ctx.frameArenas.len:
        ctx.frameArenas[frame.arenaIndex].inUse = false
        ctx.frameArenas[frame.arenaIndex].flushBufferCursor = 0

  if write < ctx.inFlightFrames.len:
    ctx.inFlightFrames.setLen(write)

proc beginFrame*(
    ctx: MetalContext,
    frameSize: Vec2,
    proj: Mat4,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  assert ctx.frameBegun == false, "ctx.beginFrame has already been called."
  ctx.frameBegun = true

  ctx.frameAutoreleasePool.start()

  ctx.ensureDeviceAndPipelines()
  ctx.ensureMask0()

  ctx.reapCompletedFrames()
  if ctx.inFlightFrames.len >= maxFramesInFlight:
    waitUntilCompleted(ctx.inFlightFrames[0].commandBuffer.borrow)
    ctx.reapCompletedFrames()

  ctx.activeArena = -1
  for i in 0 ..< ctx.frameArenas.len:
    if not ctx.frameArenas[i].inUse:
      ctx.activeArena = i
      break
  if ctx.activeArena < 0:
    ctx.activeArena = ctx.frameArenas.len
    ctx.frameArenas.add(
      FrameArena(flushBuffers: @[], flushBufferCursor: 0, inUse: false)
    )
  ctx.frameArenas[ctx.activeArena].inUse = true
  ctx.frameArenas[ctx.activeArena].flushBufferCursor = 0

  ctx.maskBegun = false
  ctx.maskTextureWrite = 0

  ctx.proj = proj
  ctx.frameSize = frameSize

  ctx.ensureOffscreen(frameSize)
  # Resize any existing mask textures > 0.
  for i in 1 ..< ctx.maskTextures.len:
    let cur = ctx.maskTextures[i]
    if cur.isNil or cur.borrow.width.int != frameSize.x.int or
        cur.borrow.height.int != frameSize.y.int:
      ctx.maskTextures[i].resetRetained(
        ctx.createMaskTexture(frameSize.x.int, frameSize.y.int)
      )

  ctx.commandBuffer.resetBorrowed(commandBuffer(ctx.queue.borrow))
  if ctx.commandBuffer.isNil:
    raise newException(ValueError, "Failed to create Metal command buffer")

  let clearMtl = MTLClearColor(
    red: clearMainColor.r.float64,
    green: clearMainColor.g.float64,
    blue: clearMainColor.b.float64,
    alpha: clearMainColor.a.float64,
  )

  # Always start in main pass.
  ctx.ensureMainPass(clear = clearMain, clearColor = clearMtl)

method beginFrame*(
    ctx: MetalContext, frameSize: Vec2, clearMain = false, clearMainColor: Color = whiteColor
) =
  beginFrame(
    ctx,
    frameSize,
    ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0),
    clearMain = clearMain,
    clearMainColor = clearMainColor,
  )

method endFrame*(ctx: MetalContext) =
  assert ctx.frameBegun == true, "ctx.beginFrame was not called first."
  assert ctx.maskTextureWrite == 0, "Not all masks have been popped."
  ctx.frameBegun = false

  ctx.flush()
  ctx.endEncoder()

  if not ctx.presentLayer.isNil:
    var drawable = ctx.presentLayer.nextDrawable()
    if drawable.isNil and not ctx.lastCommitted.isNil:
      # If we missed the drawable timeout, wait for the previous frame to
      # finish and retry once to avoid presenting a cleared frame.
      waitUntilCompleted(ctx.lastCommitted.borrow)
      drawable = ctx.presentLayer.nextDrawable()
    if not drawable.isNil:
      let pass = MTLRenderPassDescriptor.renderPassDescriptor()
      let att0 = objectAtIndexedSubscript(colorAttachments(pass), 0)
      setTexture(att0, texture(drawable))
      setLoadAction(att0, MTLLoadActionLoad)
      setStoreAction(att0, MTLStoreActionStore)
      let enc = renderCommandEncoderWithDescriptor(ctx.commandBuffer.borrow, pass)
      if not enc.isNil:
        setRenderPipelineState(enc, ctx.pipelineBlit.borrow)
        setFragmentTexture(enc, ctx.offscreenTexture.borrow, 0)
        drawPrimitives(enc, MTLPrimitiveTypeTriangle, 0, 3)
        endEncoding(enc)
      presentDrawable(ctx.commandBuffer.borrow, cast[MTLDrawable](drawable))

  commit(ctx.commandBuffer.borrow)
  ctx.lastCommitted = ctx.commandBuffer

  var inFlight = InFlightFrame()
  inFlight.commandBuffer = ctx.commandBuffer
  inFlight.arenaIndex = ctx.activeArena
  ctx.inFlightFrames.add(inFlight)
  ctx.activeArena = -1

  ctx.commandBuffer.clear()
  ctx.frameAutoreleasePool.stop()

method translate*(ctx: MetalContext, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

method rotate*(ctx: MetalContext, angle: float32) =
  ctx.mat = ctx.mat * rotateZ(angle)

method scale*(ctx: MetalContext, s: float32) =
  ctx.mat = ctx.mat * scale(vec3(s))

method scale*(ctx: MetalContext, s: Vec2) =
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))

method saveTransform*(ctx: MetalContext) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: MetalContext) =
  ctx.mat = ctx.mats.pop()

proc clearTransform*(ctx: MetalContext) =
  ctx.mat = mat4()
  ctx.mats.setLen(0)

proc fromScreen*(ctx: MetalContext, windowFrame: Vec2, v: Vec2): Vec2 =
  (ctx.mat.inverse() * vec3(v.x, windowFrame.y - v.y, 0)).xy

proc toScreen*(ctx: MetalContext, windowFrame: Vec2, v: Vec2): Vec2 =
  result = (ctx.mat * vec3(v.x, v.y, 1)).xy
  result.y = -result.y + windowFrame.y

method setPresentLayer*(ctx: MetalContext, layer: CAMetalLayer) =
  ## Optional: set a CAMetalLayer to present the offscreen result into.
  ## The caller is responsible for attaching/sizing/configuring the layer.
  ctx.presentLayer = layer

proc readPixels*(ctx: MetalContext, frame: Rect = rect(0, 0, 0, 0)): Image =
  if ctx.lastCommitted.isNil:
    raise newException(ValueError, "No Metal frame has been committed yet")
  waitUntilCompleted(ctx.lastCommitted.borrow)

  let
    texW = ctx.offscreenTexture.borrow.width.int
    texH = ctx.offscreenTexture.borrow.height.int

  var x = frame.x.int
  var y = frame.y.int
  var w = frame.w.int
  var h = frame.h.int
  if w <= 0 or h <= 0:
    x = 0
    y = 0
    w = texW
    h = texH

  x = clamp(x, 0, texW)
  y = clamp(y, 0, texH)
  w = clamp(w, 0, texW - x)
  h = clamp(h, 0, texH - y)

  result = newImage(w, h)
  var tmp = newSeq[uint8](w * h * 4)
  ctx.offscreenTexture.borrow.getBytes(
    tmp[0].addr, NSUInteger(w * 4), mtlRegion2D(x, y, w, h), 0
  )

  # Offscreen is BGRA8; Pixie expects RGBA.
  for i in 0 ..< w * h:
    let bi = i * 4
    result.data[i] = rgbx(tmp[bi + 2], tmp[bi + 1], tmp[bi + 0], tmp[bi + 3])

proc ensureFlushBufferCapacity(
    ctx: MetalContext, buffer: var ObjcOwned[MTLBuffer], capacity: var int, neededBytes: int
) =
  if neededBytes <= 0:
    return
  if not buffer.isNil and capacity >= neededBytes:
    return

  var newCapacity = max(neededBytes, 4 * 1024)
  if capacity > 0:
    newCapacity = max(newCapacity, capacity * 2)

  buffer.resetRetained(
    newBufferWithLength(
      ctx.device.borrow, NSUInteger(newCapacity), MTLResourceOptions(0)
    )
  )
  capacity = newCapacity

proc flush(ctx: MetalContext, maskTextureRead: int = ctx.maskTextureWrite) =
  if ctx.quadCount == 0:
    return

  let vertexCount = ctx.quadCount * 4
  let indexCount = ctx.quadCount * 6

  # Ensure correct pass is active.
  if ctx.maskBegun:
    ctx.ensureMaskPass(
      clear = false,
      clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
    )
  else:
    ctx.ensureMainPass(
      clear = false,
      clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
    )

  # Bind pipeline + resources.
  let enc = ctx.encoder
  if enc.isNil:
    raise newException(ValueError, "Metal render encoder is nil")

  setRenderPipelineState(
    enc, (if ctx.maskBegun: ctx.pipelineMask.borrow else: ctx.pipelineMain.borrow)
  )

  if ctx.activeArena < 0 or ctx.activeArena >= ctx.frameArenas.len:
    raise newException(ValueError, "No active Metal frame arena")

  # Reuse one buffer slot per flush within the frame arena. Arenas are reused only
  # after their command buffer has completed.
  let positionsBytes = vertexCount * 2 * sizeof(float32)
  let uvsBytes = vertexCount * 2 * sizeof(float32)
  let colorsBytes = vertexCount * 4 * sizeof(uint8)
  let sdfParamsBytes = vertexCount * 4 * sizeof(float32)
  let sdfRadiiBytes = vertexCount * 4 * sizeof(float32)
  let sdfModeBytes = vertexCount * sizeof(SdfModeData)
  let sdfFactorsBytes = vertexCount * 2 * sizeof(float32)

  var arena = addr ctx.frameArenas[ctx.activeArena]
  if arena[].flushBufferCursor >= arena[].flushBuffers.len:
    arena[].flushBuffers.setLen(arena[].flushBufferCursor + 1)
  var flushBuffers = addr arena[].flushBuffers[arena[].flushBufferCursor]
  inc arena[].flushBufferCursor

  ctx.ensureFlushBufferCapacity(
    flushBuffers[].positions, flushBuffers[].positionsCapacity, positionsBytes
  )
  ctx.ensureFlushBufferCapacity(
    flushBuffers[].uvs, flushBuffers[].uvsCapacity, uvsBytes
  )
  ctx.ensureFlushBufferCapacity(
    flushBuffers[].colors, flushBuffers[].colorsCapacity, colorsBytes
  )
  ctx.ensureFlushBufferCapacity(
    flushBuffers[].sdfParams, flushBuffers[].sdfParamsCapacity, sdfParamsBytes
  )
  ctx.ensureFlushBufferCapacity(
    flushBuffers[].sdfRadii, flushBuffers[].sdfRadiiCapacity, sdfRadiiBytes
  )
  ctx.ensureFlushBufferCapacity(
    flushBuffers[].sdfModeAttr, flushBuffers[].sdfModeAttrCapacity, sdfModeBytes
  )
  ctx.ensureFlushBufferCapacity(
    flushBuffers[].sdfFactors, flushBuffers[].sdfFactorsCapacity, sdfFactorsBytes
  )

  copyToBuf(flushBuffers[].positions.borrow, ctx.positions.data, positionsBytes)
  copyToBuf(flushBuffers[].uvs.borrow, ctx.uvs.data, uvsBytes)
  copyToBuf(flushBuffers[].colors.borrow, ctx.colors.data, colorsBytes)
  copyToBuf(flushBuffers[].sdfParams.borrow, ctx.sdfParams.data, sdfParamsBytes)
  copyToBuf(flushBuffers[].sdfRadii.borrow, ctx.sdfRadii.data, sdfRadiiBytes)
  copyToBuf(flushBuffers[].sdfModeAttr.borrow, ctx.sdfModeAttr.data, sdfModeBytes)
  copyToBuf(flushBuffers[].sdfFactors.borrow, ctx.sdfFactors.data, sdfFactorsBytes)

  setVertexBuffer(enc, flushBuffers[].positions.borrow, 0, 0)
  setVertexBuffer(enc, flushBuffers[].uvs.borrow, 0, 1)
  setVertexBuffer(enc, flushBuffers[].colors.borrow, 0, 2)
  setVertexBuffer(enc, flushBuffers[].sdfParams.borrow, 0, 3)
  setVertexBuffer(enc, flushBuffers[].sdfRadii.borrow, 0, 4)
  setVertexBuffer(enc, flushBuffers[].sdfModeAttr.borrow, 0, 5)
  setVertexBuffer(enc, flushBuffers[].sdfFactors.borrow, 0, 6)

  type VSUniforms = object
    proj: Mat4

  var vsu = VSUniforms(proj: ctx.proj)
  setVertexBytes(enc, addr vsu, NSUInteger(sizeof(VSUniforms)), 7)

  type FSUniforms = object
    windowFrame: Vec2
    aaFactor: float32
    maskTexEnabled: uint32

  var fsu = FSUniforms(
    windowFrame: ctx.frameSize,
    aaFactor: ctx.aaFactor,
    maskTexEnabled: (if maskTextureRead != 0: 1'u32 else: 0'u32),
  )
  setFragmentBytes(enc, addr fsu, NSUInteger(sizeof(FSUniforms)), 0)

  setFragmentTexture(enc, ctx.atlasTexture.borrow, 0)
  let maskIndex = clamp(maskTextureRead, 0, ctx.maskTextures.high)
  setFragmentTexture(enc, ctx.maskTextures[maskIndex].borrow, 1)

  drawIndexedPrimitives(
    enc,
    MTLPrimitiveTypeTriangle,
    NSUInteger(indexCount),
    MTLIndexTypeUInt16,
    ctx.indices.buffer.borrow,
    0,
  )

  ctx.quadCount = 0

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): MetalContext =
  if maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  withAutoreleasePool:
    result = MetalContext()
    result.atlasSize = atlasSize
    result.atlasMargin = atlasMargin
    result.maxQuads = maxQuads
    result.mat = mat4()
    result.mats = newSeq[Mat4]()
    result.pixelate = pixelate
    result.pixelScale = pixelScale
    result.aaFactor = 1.2'f32
    result.frameArenas = @[]
    result.activeArena = -1
    result.inFlightFrames = @[]

    result.ensureDeviceAndPipelines()

    result.heights = newSeq[uint16](atlasSize)
    result.atlasTexture.resetRetained(result.createAtlasTexture(atlasSize))
    result.ensureMask0()

    # Allocate CPU-side arrays.
    result.positions.data = newSeq[float32](2 * maxQuads * 4)
    result.colors.data = newSeq[uint8](4 * maxQuads * 4)
    result.uvs.data = newSeq[float32](2 * maxQuads * 4)
    result.sdfParams.data = newSeq[float32](4 * maxQuads * 4)
    result.sdfRadii.data = newSeq[float32](4 * maxQuads * 4)
    result.sdfModeAttr.data = newSeq[SdfModeData](1 * maxQuads * 4)
    result.sdfFactors.data = newSeq[float32](2 * maxQuads * 4)

    # Allocate GPU buffers.
    result.positions.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.positions.data.len * sizeof(float32)),
        MTLResourceOptions(0),
      )
    )
    result.colors.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.colors.data.len * sizeof(uint8)),
        MTLResourceOptions(0),
      )
    )
    result.uvs.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.uvs.data.len * sizeof(float32)),
        MTLResourceOptions(0),
      )
    )
    result.sdfParams.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.sdfParams.data.len * sizeof(float32)),
        MTLResourceOptions(0),
      )
    )
    result.sdfRadii.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.sdfRadii.data.len * sizeof(float32)),
        MTLResourceOptions(0),
      )
    )
    result.sdfModeAttr.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.sdfModeAttr.data.len * sizeof(SdfModeData)),
        MTLResourceOptions(0),
      )
    )
    result.sdfFactors.buffer.resetRetained(
      newBufferWithLength(
        result.device.borrow,
        NSUInteger(result.sdfFactors.data.len * sizeof(float32)),
        MTLResourceOptions(0),
      )
    )

    # Indices are static.
    result.indices.data = newSeq[uint16](maxQuads * 6)
    for i in 0 ..< maxQuads:
      let offset = i * 4
      let base = i * 6
      result.indices.data[base + 0] = (offset + 3).uint16
      result.indices.data[base + 1] = (offset + 0).uint16
      result.indices.data[base + 2] = (offset + 1).uint16
      result.indices.data[base + 3] = (offset + 2).uint16
      result.indices.data[base + 4] = (offset + 3).uint16
      result.indices.data[base + 5] = (offset + 1).uint16

    result.indices.buffer.resetRetained(
      newBufferWithBytes(
        result.device.borrow,
        result.indices.data[0].addr,
        NSUInteger(result.indices.data.len * sizeof(uint16)),
        MTLResourceOptions(0),
      )
    )

method kind*(ctx: MetalContext): figbackend.RendererBackendKind =
  figbackend.RendererBackendKind.rbMetal

method entriesPtr*(ctx: MetalContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method pixelScale*(ctx: MetalContext): float32 =
  ctx.pixelScale

method readPixels*(ctx: MetalContext, frame: Rect, readFront: bool): Image =
  discard readFront
  readPixels(ctx, frame)
