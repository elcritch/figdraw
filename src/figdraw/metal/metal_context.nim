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

type RectMaskKind = enum
  rmkFast
  rmkMask

type RectMask = object
  kind: RectMaskKind
  params: Vec4
  radii: Vec4
  matX: Vec4
  matY: Vec4

type CpuBuffer[T] = object
  data: seq[T]

type FlushBuffers = object
  data: ObjcOwned[MTLBuffer]
  capacity: int

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
  pipelineMainRectMask: ObjcOwned[MTLRenderPipelineState]
  pipelineMask: ObjcOwned[MTLRenderPipelineState]
  pipelineBlit: ObjcOwned[MTLRenderPipelineState]
  pipelineBlur: ObjcOwned[MTLRenderPipelineState]

  # Optional presentation target.
  # Windowing code owns attaching/sizing this layer.
  presentLayer*: CAMetalLayer

  # Render targets
  offscreenTexture: ObjcOwned[MTLTexture]
  backdropTexture: ObjcOwned[MTLTexture]
  backdropBlurTempTexture: ObjcOwned[MTLTexture]
  atlasTexture: ObjcOwned[MTLTexture]
  maskTextures: seq[ObjcOwned[MTLTexture]]
  maskTextureWrite: int ## Index of active mask stack (0 means no mask).

  atlasSize: int
  initialAtlasSize: int
  atlasMargin: int
  quadCount: int
  maxQuads: int
  mat*: Mat4
  mats: seq[Mat4]
  entries*: Table[Hash, Rect]
  atlasEntryMeta: Table[Hash, AtlasEntryMeta]
  heights: seq[uint16]
  proj*: Mat4
  frameSize: Vec2
  frameBegun, maskBegun: bool
  batchHasRectMask: bool
  pixelate*: bool
  pixelScale*: float32

  # Buffer data mirrored on CPU and uploaded each flush.
  indices: tuple[buffer: ObjcOwned[MTLBuffer], data: seq[uint16]]
  positions: CpuBuffer[float32]
  colors: CpuBuffer[uint8]
  fillMidColors: CpuBuffer[uint8]
  fillStopColors: CpuBuffer[uint8]
  uvs: CpuBuffer[float32]
  sdfParams: CpuBuffer[float32]
  sdfRadii: CpuBuffer[float32]
  sdfModeAttr: CpuBuffer[SdfModeData]
  sdfFactors: CpuBuffer[float32]
  rectMaskParams: CpuBuffer[float32]
  rectMaskRadii: CpuBuffer[float32]
  rectMaskMatX: CpuBuffer[float32]
  rectMaskMatY: CpuBuffer[float32]
  rectMaskStack: seq[RectMask]

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
proc beginPass(
  ctx: MetalContext,
  kind: PassKind,
  target: MTLTexture,
  clear: bool,
  clearColor: MTLClearColor,
)

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

proc ensureBackdropTexture(ctx: MetalContext, frameSize: Vec2) =
  let w = max(1, frameSize.x.int)
  let h = max(1, frameSize.y.int)
  if not ctx.backdropTexture.isNil:
    if ctx.backdropTexture.borrow.width.int == w and
        ctx.backdropTexture.borrow.height.int == h:
      return
  ctx.backdropTexture.resetRetained(
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

proc ensureBackdropBlurTempTexture(ctx: MetalContext, frameSize: Vec2) =
  let w = max(1, frameSize.x.int)
  let h = max(1, frameSize.y.int)
  if not ctx.backdropBlurTempTexture.isNil:
    if ctx.backdropBlurTempTexture.borrow.width.int == w and
        ctx.backdropBlurTempTexture.borrow.height.int == h:
      return
  ctx.backdropBlurTempTexture.resetRetained(
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

proc blitToTexture(ctx: MetalContext, src: MTLTexture, dst: MTLTexture) =
  if src.isNil or dst.isNil:
    return
  ctx.beginPass(
    pkBlit,
    dst,
    clear = false,
    clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
  )
  let enc = ctx.encoder
  if enc.isNil:
    return
  setRenderPipelineState(enc, ctx.pipelineBlit.borrow)
  setFragmentTexture(enc, src, 0)
  drawPrimitives(enc, MTLPrimitiveTypeTriangle, 0, 3)

proc runBackdropSeparableBlur(ctx: MetalContext, blurRadius: float32) =
  if blurRadius <= 0.5'f32:
    return
  if ctx.backdropTexture.isNil:
    return

  ctx.ensureBackdropBlurTempTexture(ctx.frameSize)

  type BlurUniforms = object
    texelStep: Vec2
    blurRadius: float32
    pad0: float32

  let
    w = max(1.0'f32, ctx.frameSize.x)
    h = max(1.0'f32, ctx.frameSize.y)
    clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)

  # Horizontal pass.
  ctx.beginPass(
    pkBlit, ctx.backdropBlurTempTexture.borrow, clear = false, clearColor = clearColor
  )
  var enc = ctx.encoder
  if enc.isNil:
    return
  setRenderPipelineState(enc, ctx.pipelineBlur.borrow)
  setFragmentTexture(enc, ctx.backdropTexture.borrow, 0)
  var blurU = BlurUniforms(
    texelStep: vec2(1.0'f32 / w, 0.0'f32), blurRadius: blurRadius, pad0: 0.0'f32
  )
  setFragmentBytes(enc, addr blurU, NSUInteger(sizeof(BlurUniforms)), 0)
  drawPrimitives(enc, MTLPrimitiveTypeTriangle, 0, 3)

  # Vertical pass.
  ctx.beginPass(
    pkBlit, ctx.backdropTexture.borrow, clear = false, clearColor = clearColor
  )
  enc = ctx.encoder
  if enc.isNil:
    return
  setRenderPipelineState(enc, ctx.pipelineBlur.borrow)
  setFragmentTexture(enc, ctx.backdropBlurTempTexture.borrow, 0)
  blurU.texelStep = vec2(0.0'f32, 1.0'f32 / h)
  setFragmentBytes(enc, addr blurU, NSUInteger(sizeof(BlurUniforms)), 0)
  drawPrimitives(enc, MTLPrimitiveTypeTriangle, 0, 3)

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
      not ctx.pipelineMainRectMask.isNil and not ctx.pipelineMask.isNil and
      not ctx.pipelineBlit.isNil and not ctx.pipelineBlur.isNil:
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
    let vsRectMask = fromRetained(
      newFunctionWithName(
        library.borrow, NSString.withUTF8String(cstring("vs_rect_mask"))
      )
    )
    let fsMain = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("fs_main")))
    )
    let fsRectMask = fromRetained(
      newFunctionWithName(
        library.borrow, NSString.withUTF8String(cstring("fs_rect_mask"))
      )
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
    let fsBlur = fromRetained(
      newFunctionWithName(library.borrow, NSString.withUTF8String(cstring("fs_blur")))
    )
    if vsMain.isNil or vsRectMask.isNil or fsMain.isNil or fsRectMask.isNil or
        fsMask.isNil or vsBlit.isNil or fsBlit.isNil or fsBlur.isNil:
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

    # Main pipeline with per-vertex rect mask data (offscreen BGRA8).
    block:
      let pd = fromRetained(MTLRenderPipelineDescriptor.alloc().init())
      setVertexFunction(pd.borrow, vsRectMask.borrow)
      setFragmentFunction(pd.borrow, fsRectMask.borrow)
      let ca0 = objectAtIndexedSubscript(colorAttachments(pd.borrow), 0)
      setPixelFormat(ca0, MTLPixelFormatBGRA8Unorm)
      configureBlend(ca0)
      ctx.pipelineMainRectMask.resetRetained(
        newRenderPipelineStateWithDescriptor(ctx.device.borrow, pd.borrow, addr err)
      )
      if ctx.pipelineMainRectMask.isNil:
        if not err.isNil:
          error "Failed to create Metal rect-mask pipeline", error = $err
        raise newException(ValueError, "Failed to create Metal rect-mask pipeline")

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

    # Blur pipeline (BGRA8, no blending).
    block:
      let pd = fromRetained(MTLRenderPipelineDescriptor.alloc().init())
      setVertexFunction(pd.borrow, vsBlit.borrow)
      setFragmentFunction(pd.borrow, fsBlur.borrow)
      let ca0 = objectAtIndexedSubscript(colorAttachments(pd.borrow), 0)
      setPixelFormat(ca0, MTLPixelFormatBGRA8Unorm)
      ctx.pipelineBlur.resetRetained(
        newRenderPipelineStateWithDescriptor(ctx.device.borrow, pd.borrow, addr err)
      )
      if ctx.pipelineBlur.isNil:
        if not err.isNil:
          error "Failed to create Metal blur pipeline", error = $err
        raise newException(ValueError, "Failed to create Metal blur pipeline")

proc grow(ctx: MetalContext) =
  let nextSize = ctx.atlasSize * 2
  ctx.resetImageAtlas(nextSize)
  info "grow atlasSize ", atlasSize = ctx.atlasSize

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
  ctx.markGeneratedEntry(path)
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
  ctx.markImageEntry(imgObj.id)

method clearImageAtlas*(ctx: MetalContext) =
  ctx.resetImageAtlas(ctx.initialAtlasSize)

method resetImageAtlas*(ctx: MetalContext, minimumSize: int) =
  ctx.flush()
  ctx.atlasSize = plannedAtlasSize(ctx.initialAtlasSize, minimumSize)
  ctx.entries.clear()
  ctx.atlasEntryMeta.clear()
  ctx.heights = newSeq[uint16](ctx.atlasSize)
  ctx.atlasTexture.resetRetained(ctx.createAtlasTexture(ctx.atlasSize))
  ctx.noteAtlasRebuilt()

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

func roundedRadiiVec(radii: array[DirectionCorners, float32], halfExtents: Vec2): Vec4 =
  let maxRadius = min(halfExtents.x, halfExtents.y)
  let radiiClamped = [
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
  vec4(
    radiiClamped[dcTopRight],
    radiiClamped[dcBottomRight],
    radiiClamped[dcTopLeft],
    radiiClamped[dcBottomLeft],
  )

const
  SdfEllipseFlag = 128
  SdfRadiusQuantization = 4095.0'f32
  SdfRadiusQuantizationBase = 4096.0'f32

func roundedRadius(radius, maximum: float32): float32 =
  if radius <= 0.0'f32:
    0.0'f32
  else:
    max(1.0'f32, min(radius, maximum)).round()

func packEllipticalRadius(rx, ry: float32, halfExtents: Vec2): float32 =
  let
    qx = round(
      clamp(rx / max(halfExtents.x, 0.000001'f32), 0.0'f32, 1.0'f32) *
        SdfRadiusQuantization
    )
    qy = round(
      clamp(ry / max(halfExtents.y, 0.000001'f32), 0.0'f32, 1.0'f32) *
        SdfRadiusQuantization
    )
  qx + qy * SdfRadiusQuantizationBase

func packCircularRadius(radius: float32): float32 =
  ## Negative values preserve a circular corner inside an otherwise elliptical
  ## primitive without consuming another vertex attribute.
  -(radius + 1.0'f32)

func roundedRadiiVec(
    radii: CornerRadii2D[float32], halfExtents: Vec2
): tuple[radii: Vec4, elliptical: bool] =
  var allCircular = true
  for corner in DirectionCorners:
    if radii.x[corner] != radii.y[corner]:
      allCircular = false

  if allCircular:
    return (roundedRadiiVec(radii.x, halfExtents), false)

  let radiiX = [
    dcTopLeft: roundedRadius(radii.x[dcTopLeft], halfExtents.x),
    dcTopRight: roundedRadius(radii.x[dcTopRight], halfExtents.x),
    dcBottomLeft: roundedRadius(radii.x[dcBottomLeft], halfExtents.x),
    dcBottomRight: roundedRadius(radii.x[dcBottomRight], halfExtents.x),
  ]
  let radiiY = [
    dcTopLeft: roundedRadius(radii.y[dcTopLeft], halfExtents.y),
    dcTopRight: roundedRadius(radii.y[dcTopRight], halfExtents.y),
    dcBottomLeft: roundedRadius(radii.y[dcBottomLeft], halfExtents.y),
    dcBottomRight: roundedRadius(radii.y[dcBottomRight], halfExtents.y),
  ]
  let circleMaxRadius = min(halfExtents.x, halfExtents.y)
  func encodeCorner(corner: DirectionCorners): float32 =
    let
      sameInputAxes = radii.x[corner] == radii.y[corner]
      circleRadius = roundedRadius(radii.x[corner], circleMaxRadius)
    if sameInputAxes:
      return packCircularRadius(circleRadius)
    if radiiX[corner] == radiiY[corner]:
      return packCircularRadius(radiiX[corner])
    packEllipticalRadius(radiiX[corner], radiiY[corner], halfExtents)
  (
    vec4(
      encodeCorner(dcTopRight),
      encodeCorner(dcBottomRight),
      encodeCorner(dcTopLeft),
      encodeCorner(dcBottomLeft),
    ),
    true,
  )

proc makeRectMask(
    ctx: MetalContext, maskRect: Rect, radii: CornerRadii2D[float32]
): RectMask =
  let
    halfExtents = maskRect.wh * 0.5'f32
    center = maskRect.xy + halfExtents
    invMat = ctx.mat.inverse()
    encodedRadii = roundedRadiiVec(radii, halfExtents)
  RectMask(
    kind: rmkFast,
    params: vec4(center.x, center.y, halfExtents.x, halfExtents.y),
    radii: encodedRadii.radii,
    matX: vec4(invMat[0, 0], invMat[1, 0], invMat[3, 0], 1.0'f32),
    matY: vec4(
      invMat[0, 1],
      invMat[1, 1],
      invMat[3, 1],
      if encodedRadii.elliptical: 1.0'f32 else: 0.0'f32,
    ),
  )

proc setRectMaskVert4(ctx: MetalContext, offset: int, params, radii, matX, matY: Vec4) =
  for i in 0 ..< 4:
    ctx.rectMaskParams.data.setVert4(offset + i, params)
    ctx.rectMaskRadii.data.setVert4(offset + i, radii)
    ctx.rectMaskMatX.data.setVert4(offset + i, matX)
    ctx.rectMaskMatY.data.setVert4(offset + i, matY)

proc setDisabledRectMaskVerts(ctx: MetalContext, firstVertex, vertexCount: int) =
  let
    params = vec4(0.0'f32, 0.0'f32, -1.0'f32, -1.0'f32)
    zero4 = vec4(0.0'f32)
  for i in firstVertex ..< firstVertex + vertexCount:
    ctx.rectMaskParams.data.setVert4(i, params)
    ctx.rectMaskRadii.data.setVert4(i, zero4)
    ctx.rectMaskMatX.data.setVert4(i, zero4)
    ctx.rectMaskMatY.data.setVert4(i, zero4)

proc setRectMaskVert4(ctx: MetalContext, offset: int) =
  if ctx.maskBegun:
    return

  var
    hasRectMask = false
    params = vec4(0.0'f32)
    radii = vec4(0.0'f32)
    matX = vec4(0.0'f32)
    matY = vec4(0.0'f32)

  if ctx.rectMaskStack.len > 0:
    for i in countdown(ctx.rectMaskStack.len - 1, 0):
      let rectMask = ctx.rectMaskStack[i]
      if rectMask.kind == rmkFast:
        hasRectMask = true
        params = rectMask.params
        radii = rectMask.radii
        matX = rectMask.matX
        matY = rectMask.matY
        break

  if hasRectMask:
    if not ctx.batchHasRectMask:
      ctx.setDisabledRectMaskVerts(0, offset)
      ctx.batchHasRectMask = true
    ctx.setRectMaskVert4(offset, params, radii, matX, matY)
  elif ctx.batchHasRectMask:
    ctx.setDisabledRectMaskVerts(offset, 4)

template setRectMaskVert4IfNeeded(ctx: MetalContext, offset: int) =
  if not ctx.maskBegun and (ctx.batchHasRectMask or ctx.rectMaskStack.len > 0):
    ctx.setRectMaskVert4(offset)

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
  ctx.setRectMaskVert4IfNeeded(offset)

  inc ctx.quadCount

method drawFilledQuad*(
    ctx: MetalContext, verts: array[4, Vec2], colors: array[4, ColorRGBA]
) =
  const imgKey = hash("rect")
  if imgKey notin ctx.entries:
    var image = newImage(4, 4)
    image.fill(rgba(255, 255, 255, 255))
    ctx.putImage(imgKey, image)

  let
    uv = ctx.entries[imgKey].xy + ctx.entries[imgKey].wh / 2.0'f32
    uvQuad = [uv, uv, uv, uv]

  let posQuad = [
    ceil(ctx.mat * verts[0]),
    ceil(ctx.mat * verts[1]),
    ceil(ctx.mat * verts[2]),
    ceil(ctx.mat * verts[3]),
  ]
  ctx.drawQuad(posQuad, uvQuad, colors)

type SdfMode* = figbackend.SdfMode

const
  SdfFillSolidOrVertex = 0
  SdfFillLinear3X = 1
  SdfFillLinear3Y = 2
  SdfFillLinear3DiagTLBR = 3
  SdfFillLinear3DiagBLTR = 4
  SdfFillModeShift = 256

func linear3FillMode(axis: FillGradientAxis): int =
  case axis
  of fgaX: SdfFillLinear3X
  of fgaY: SdfFillLinear3Y
  of fgaDiagTLBR: SdfFillLinear3DiagTLBR
  of fgaDiagBLTR: SdfFillLinear3DiagBLTR

func encodeSdfMode(
    mode: SdfMode, fillMode: int, elliptical: bool = false
): SdfModeData =
  let packed =
    mode.int + (if elliptical: SdfEllipseFlag else: 0) + fillMode * SdfFillModeShift
  when SdfModeData is float32: packed.float32 else: packed.uint16

proc setFillExtraColors(
    ctx: MetalContext, offset: int, midColor, stopColor: ColorRGBA
) =
  ctx.fillMidColors.data.setVertColor(offset + 0, midColor)
  ctx.fillMidColors.data.setVertColor(offset + 1, midColor)
  ctx.fillMidColors.data.setVertColor(offset + 2, midColor)
  ctx.fillMidColors.data.setVertColor(offset + 3, midColor)
  ctx.fillStopColors.data.setVertColor(offset + 0, stopColor)
  ctx.fillStopColors.data.setVertColor(offset + 1, stopColor)
  ctx.fillStopColors.data.setVertColor(offset + 2, stopColor)
  ctx.fillStopColors.data.setVertColor(offset + 3, stopColor)

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
  ctx.setRectMaskVert4IfNeeded(offset)

  inc ctx.quadCount

proc imageUvBounds(rect: Rect, flipY: bool): tuple[uvAt: Vec2, uvTo: Vec2]

method drawMsdfImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
    strokeWeight: float32 = 0.0'f32,
    flipY: bool = false,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let (uvAt, uvTo) = imageUvBounds(rect, flipY)
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMsdfAnnular else: SdfMode.sdfModeMsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = uvAt,
    uvTo = uvTo,
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
    flipY: bool = false,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let (uvAt, uvTo) = imageUvBounds(rect, flipY)
  let strokeW = max(0.0'f32, strokeWeight)
  let params = vec4(ctx.atlasSize.float32, strokeW, 0.0'f32, 0.0'f32)
  let modeSel: SdfMode =
    if strokeW > 0.0'f32: SdfMode.sdfModeMtsdfAnnular else: SdfMode.sdfModeMtsdf
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = uvAt,
    uvTo = uvTo,
    color = color,
    mode = modeSel,
    factors = vec2(pxRange, sdThreshold),
    params = params,
  )

method sdfAaFactor*(ctx: MetalContext): float32 =
  ctx.aaFactor

method setSdfAaFactor*(ctx: MetalContext, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.flush()
  ctx.aaFactor = aaFactor

proc setSdfGlobals*(ctx: MetalContext, aaFactor: float32) =
  ctx.setSdfAaFactor(aaFactor)

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
  ctx.setRectMaskVert4IfNeeded(offset)

  inc ctx.quadCount

proc drawUvRect(
    ctx: MetalContext, at, to: Vec2, uvAt, uvTo: Vec2, colors: array[4, ColorRGBA]
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

  ctx.colors.data.setVertColor(offset + 0, colors[0])
  ctx.colors.data.setVertColor(offset + 1, colors[1])
  ctx.colors.data.setVertColor(offset + 2, colors[2])
  ctx.colors.data.setVertColor(offset + 3, colors[3])

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
  ctx.setRectMaskVert4IfNeeded(offset)

  inc ctx.quadCount

proc drawUvRect(ctx: MetalContext, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc drawUvRect(ctx: MetalContext, rect, uvRect: Rect, colors: array[4, ColorRGBA]) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, colors)

proc tryGetImageRect(ctx: MetalContext, imageId: Hash, rect: var Rect): bool =
  if imageId notin ctx.entries:
    warn "missing image in context", imageId = imageId
    return false
  rect = ctx.entries[imageId]
  true

proc imageUvBounds(rect: Rect, flipY: bool): tuple[uvAt: Vec2, uvTo: Vec2] =
  if flipY:
    return (vec2(rect.x, rect.y + rect.h), vec2(rect.x + rect.w, rect.y))
  (rect.xy, rect.xy + rect.wh)

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

proc drawImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    colors: array[4, ColorRGBA],
    scale: float32,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, colors)

method drawImage*(
    ctx: MetalContext,
    imageId: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let drawSize =
    if size.x > 0.0'f32 and size.y > 0.0'f32:
      size
    else:
      rect.wh * ctx.atlasSize.float32
  let (uvAt, uvTo) = imageUvBounds(rect, flipY)
  ctx.drawUvRect(pos, pos + drawSize, uvAt, uvTo, colors)

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
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  let rgba = color.rgba()
  ctx.drawRoundedRectSdf(
    rect = rect,
    colors = [rgba, rgba, rgba, rgba],
    radii = radii,
    mode = mode,
    factor = factor,
    spread = spread,
    shapeSize = shapeSize,
  )

proc drawRoundedRectSdfMetal(
    ctx: MetalContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
    fillMode: int = SdfFillSolidOrVertex,
    fillMidColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillStopColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillMidPos: float32 = 0.5'f32,
) =
  if rect.w <= 0 or rect.h <= 0:
    return

  ctx.checkBatch()

  let
    quadHalfExtents = rect.wh * 0.5'f32
    insetMode = mode == sdfModeInsetShadow
    resolvedShapeSize =
      (if shapeSize.x > 0.0'f32 and shapeSize.y > 0.0'f32: shapeSize else: rect.wh)
    shapeHalfExtents =
      if insetMode:
        quadHalfExtents
      else:
        resolvedShapeSize * 0.5'f32
    params =
      if insetMode:
        # In inset mode, params.zw carry shadow offset (x, y) in screen space.
        vec4(quadHalfExtents.x, quadHalfExtents.y, shapeSize.x, shapeSize.y)
      else:
        vec4(
          quadHalfExtents.x, quadHalfExtents.y, shapeHalfExtents.x, shapeHalfExtents.y
        )
    encodedRadii = roundedRadiiVec(radii, shapeHalfExtents)

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

  ctx.colors.data.setVertColor(offset + 0, colors[0])
  ctx.colors.data.setVertColor(offset + 1, colors[1])
  ctx.colors.data.setVertColor(offset + 2, colors[2])
  ctx.colors.data.setVertColor(offset + 3, colors[3])
  ctx.setFillExtraColors(offset, fillMidColor, fillStopColor)

  ctx.sdfParams.data.setVert4(offset + 0, params)
  ctx.sdfParams.data.setVert4(offset + 1, params)
  ctx.sdfParams.data.setVert4(offset + 2, params)
  ctx.sdfParams.data.setVert4(offset + 3, params)

  ctx.sdfRadii.data.setVert4(offset + 0, encodedRadii.radii)
  ctx.sdfRadii.data.setVert4(offset + 1, encodedRadii.radii)
  ctx.sdfRadii.data.setVert4(offset + 2, encodedRadii.radii)
  ctx.sdfRadii.data.setVert4(offset + 3, encodedRadii.radii)

  let factors =
    if fillMode == SdfFillSolidOrVertex:
      vec2(factor, spread)
    else:
      vec2(factor, clamp(fillMidPos, 0.01'f32, 0.99'f32))
  ctx.sdfFactors.data.setVert2(offset + 0, factors)
  ctx.sdfFactors.data.setVert2(offset + 1, factors)
  ctx.sdfFactors.data.setVert2(offset + 2, factors)
  ctx.sdfFactors.data.setVert2(offset + 3, factors)

  let modeVal = encodeSdfMode(mode, fillMode, encodedRadii.elliptical)
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal
  ctx.setRectMaskVert4IfNeeded(offset)

  inc ctx.quadCount

method drawRoundedRectSdf*(
    ctx: MetalContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  ctx.drawRoundedRectSdfMetal(
    rect = rect,
    colors = colors,
    radii = radii,
    mode = mode,
    factor = factor,
    spread = spread,
    shapeSize = shapeSize,
  )

method drawRoundedRectSdf*(
    ctx: MetalContext,
    rect: Rect,
    fill: figbackend.BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode = sdfModeClipAA,
    factor: float32 = 4.0,
    spread: float32 = 0.0,
    shapeSize: Vec2 = vec2(0.0'f32, 0.0'f32),
) =
  if fill.kind == figbackend.bfLinear3 and
      mode in {sdfModeClipAA, sdfModeAnnular, sdfModeAnnularAA}:
    ctx.drawRoundedRectSdfMetal(
      rect = rect,
      colors = [fill.lin3Start, fill.lin3Start, fill.lin3Start, fill.lin3Start],
      radii = radii,
      mode = mode,
      factor = factor,
      spread = spread,
      shapeSize = shapeSize,
      fillMode = linear3FillMode(fill.lin3Axis),
      fillMidColor = fill.lin3Mid,
      fillStopColor = fill.lin3Stop,
      fillMidPos = fill.lin3MidPos,
    )
  else:
    ctx.drawRoundedRectSdfMetal(
      rect = rect,
      colors = figbackend.gradientColors(fill),
      radii = radii,
      mode = mode,
      factor = factor,
      spread = spread,
      shapeSize = shapeSize,
    )

proc drawQuadraticBezierSdfMetal(
    ctx: MetalContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
    fillMode: int = SdfFillSolidOrVertex,
    fillMidColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillStopColor: ColorRGBA = rgba(0, 0, 0, 0),
    fillMidPos: float32 = 0.5'f32,
) =
  if rect.w <= 0.0'f32 or rect.h <= 0.0'f32 or strokeWeight <= 0.0'f32:
    return

  ctx.checkBatch()

  let
    quadHalfExtents = rect.wh * 0.5'f32
    params = vec4(quadHalfExtents.x, quadHalfExtents.y, p0.x, p0.y)
    curve = vec4(p1.x, p1.y, p2.x, p2.y)

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

  ctx.colors.data.setVertColor(offset + 0, colors[0])
  ctx.colors.data.setVertColor(offset + 1, colors[1])
  ctx.colors.data.setVertColor(offset + 2, colors[2])
  ctx.colors.data.setVertColor(offset + 3, colors[3])
  ctx.setFillExtraColors(offset, fillMidColor, fillStopColor)

  ctx.sdfParams.data.setVert4(offset + 0, params)
  ctx.sdfParams.data.setVert4(offset + 1, params)
  ctx.sdfParams.data.setVert4(offset + 2, params)
  ctx.sdfParams.data.setVert4(offset + 3, params)

  ctx.sdfRadii.data.setVert4(offset + 0, curve)
  ctx.sdfRadii.data.setVert4(offset + 1, curve)
  ctx.sdfRadii.data.setVert4(offset + 2, curve)
  ctx.sdfRadii.data.setVert4(offset + 3, curve)

  let factors =
    if fillMode == SdfFillSolidOrVertex:
      vec2(strokeWeight, 0.0'f32)
    else:
      vec2(strokeWeight, clamp(fillMidPos, 0.01'f32, 0.99'f32))
  ctx.sdfFactors.data.setVert2(offset + 0, factors)
  ctx.sdfFactors.data.setVert2(offset + 1, factors)
  ctx.sdfFactors.data.setVert2(offset + 2, factors)
  ctx.sdfFactors.data.setVert2(offset + 3, factors)

  let modeVal = encodeSdfMode(figbackend.bezierStrokeSdfMode(cap), fillMode)
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal
  ctx.setRectMaskVert4IfNeeded(offset)

  inc ctx.quadCount

method drawQuadraticBezierSdf*(
    ctx: MetalContext,
    rect: Rect,
    fill: figbackend.BackendFill,
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
) =
  if fill.kind == figbackend.bfLinear3:
    ctx.drawQuadraticBezierSdfMetal(
      rect = rect,
      colors = [fill.lin3Start, fill.lin3Start, fill.lin3Start, fill.lin3Start],
      p0 = p0,
      p1 = p1,
      p2 = p2,
      strokeWeight = strokeWeight,
      cap = cap,
      fillMode = linear3FillMode(fill.lin3Axis),
      fillMidColor = fill.lin3Mid,
      fillStopColor = fill.lin3Stop,
      fillMidPos = fill.lin3MidPos,
    )
  else:
    ctx.drawQuadraticBezierSdfMetal(
      rect = rect,
      colors = figbackend.gradientColors(fill),
      p0 = p0,
      p1 = p1,
      p2 = p2,
      strokeWeight = strokeWeight,
      cap = cap,
    )

method drawBackdropBlur*(
    ctx: MetalContext, rect: Rect, radii: CornerRadii2D[float32], blurRadius: float32
) =
  if blurRadius <= 0.0'f32 or rect.w <= 0.0'f32 or rect.h <= 0.0'f32:
    return

  ctx.flush()
  if ctx.commandBuffer.isNil or ctx.offscreenTexture.isNil:
    return

  ctx.ensureBackdropTexture(ctx.frameSize)
  ctx.blitToTexture(ctx.offscreenTexture.borrow, ctx.backdropTexture.borrow)
  ctx.runBackdropSeparableBlur(blurRadius)

  ctx.drawRoundedRectSdf(
    rect = rect,
    color = whiteColor,
    radii = radii,
    mode = figbackend.SdfMode.sdfModeBackdropBlur,
    factor = blurRadius,
    spread = 0.0'f32,
    shapeSize = vec2(0.0'f32, 0.0'f32),
  )

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

method beginMask*(ctx: MetalContext, clipRect: Rect, radii: CornerRadii2D[float32]) =
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

method beginRectMask*(
    ctx: MetalContext, maskRect: Rect, radii: CornerRadii2D[float32]
) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginRectMask cannot start inside a mask."

  if ctx.rectMaskStack.len == 0 and maskRect.w > 0.0'f32 and maskRect.h > 0.0'f32:
    ctx.rectMaskStack.add(ctx.makeRectMask(maskRect, radii))
  else:
    ctx.beginMask(maskRect, radii)
    ctx.endMask()
    ctx.rectMaskStack.add(RectMask(kind: rmkMask))

method popRectMask*(ctx: MetalContext) =
  assert ctx.rectMaskStack.len > 0, "No rect mask has been pushed."
  let rectMask = ctx.rectMaskStack.pop()
  if rectMask.kind == rmkMask:
    ctx.popMask()

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
  ctx.rectMaskStack.setLen(0)
  ctx.batchHasRectMask = false

  ctx.proj = proj
  ctx.frameSize = frameSize

  ctx.ensureOffscreen(frameSize)
  ctx.ensureBackdropTexture(frameSize)
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
    ctx: MetalContext,
    frameSize: Vec2,
    clearMain = false,
    clearMainColor: Color = whiteColor,
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
  assert ctx.rectMaskStack.len == 0, "Not all rect masks have been popped."
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

method applyTransform*(ctx: MetalContext, m: Mat4) =
  ctx.mat = ctx.mat * m

method saveTransform*(ctx: MetalContext) =
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: MetalContext) =
  ctx.mat = ctx.mats.pop()

method transformMirrorsY*(ctx: MetalContext): bool =
  let origin = (ctx.mat * vec3(0.0'f32, 0.0'f32, 1.0'f32)).xy
  let xAxis = (ctx.mat * vec3(1.0'f32, 0.0'f32, 1.0'f32)).xy - origin
  let yAxis = (ctx.mat * vec3(0.0'f32, 1.0'f32, 1.0'f32)).xy - origin
  let determinant = xAxis.x * yAxis.y - xAxis.y * yAxis.x
  determinant < 0.0'f32

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
    ctx: MetalContext,
    buffer: var ObjcOwned[MTLBuffer],
    capacity: var int,
    neededBytes: int,
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

func alignedUploadOffset(offset: int): int {.inline.} =
  (offset + 15) and not 15

proc copyToUpload[T](base: pointer, offset: int, src: seq[T], bytes: int) {.inline.} =
  if bytes <= 0:
    return
  assert not base.isNil, "MTLBuffer cannot be nil"
  assert src.len * sizeof(T) >= bytes, "buffer src too small"
  let dst = cast[pointer](cast[uint](base) + offset.uint)
  copyMem(dst, src[0].addr, bytes)

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

  let useRectMaskPipeline = not ctx.maskBegun and ctx.batchHasRectMask
  setRenderPipelineState(
    enc,
    (
      if ctx.maskBegun:
        ctx.pipelineMask.borrow
      elif useRectMaskPipeline:
        ctx.pipelineMainRectMask.borrow
      else:
        ctx.pipelineMain.borrow
    ),
  )

  if ctx.activeArena < 0 or ctx.activeArena >= ctx.frameArenas.len:
    raise newException(ValueError, "No active Metal frame arena")

  # Reuse one buffer slot per flush within the frame arena. Arenas are reused only
  # after their command buffer has completed. Attributes remain structure-of-arrays
  # for efficient vertex fetches, but share one Metal allocation.
  let
    positionsBytes = vertexCount * 2 * sizeof(float32)
    uvsBytes = vertexCount * 2 * sizeof(float32)
    colorsBytes = vertexCount * 4 * sizeof(uint8)
    fillMidColorsBytes = vertexCount * 4 * sizeof(uint8)
    fillStopColorsBytes = vertexCount * 4 * sizeof(uint8)
    sdfParamsBytes = vertexCount * 4 * sizeof(float32)
    sdfRadiiBytes = vertexCount * 4 * sizeof(float32)
    sdfModeBytes = vertexCount * sizeof(SdfModeData)
    sdfFactorsBytes = vertexCount * 2 * sizeof(float32)
    rectMaskParamsBytes =
      if useRectMaskPipeline:
        vertexCount * 4 * sizeof(float32)
      else:
        0
    rectMaskRadiiBytes = rectMaskParamsBytes
    rectMaskMatXBytes = rectMaskParamsBytes
    rectMaskMatYBytes = rectMaskParamsBytes

    positionsOffset = 0
    uvsOffset = alignedUploadOffset(positionsOffset + positionsBytes)
    colorsOffset = alignedUploadOffset(uvsOffset + uvsBytes)
    fillMidColorsOffset = alignedUploadOffset(colorsOffset + colorsBytes)
    fillStopColorsOffset = alignedUploadOffset(fillMidColorsOffset + fillMidColorsBytes)
    sdfParamsOffset = alignedUploadOffset(fillStopColorsOffset + fillStopColorsBytes)
    sdfRadiiOffset = alignedUploadOffset(sdfParamsOffset + sdfParamsBytes)
    sdfModeOffset = alignedUploadOffset(sdfRadiiOffset + sdfRadiiBytes)
    sdfFactorsOffset = alignedUploadOffset(sdfModeOffset + sdfModeBytes)
    rectMaskParamsOffset = alignedUploadOffset(sdfFactorsOffset + sdfFactorsBytes)
    rectMaskRadiiOffset =
      alignedUploadOffset(rectMaskParamsOffset + rectMaskParamsBytes)
    rectMaskMatXOffset = alignedUploadOffset(rectMaskRadiiOffset + rectMaskRadiiBytes)
    rectMaskMatYOffset = alignedUploadOffset(rectMaskMatXOffset + rectMaskMatXBytes)
    uploadBytes = alignedUploadOffset(rectMaskMatYOffset + rectMaskMatYBytes)

  var arena = addr ctx.frameArenas[ctx.activeArena]
  if arena[].flushBufferCursor >= arena[].flushBuffers.len:
    arena[].flushBuffers.setLen(arena[].flushBufferCursor + 1)
  var flushBuffers = addr arena[].flushBuffers[arena[].flushBufferCursor]
  inc arena[].flushBufferCursor

  ctx.ensureFlushBufferCapacity(
    flushBuffers[].data, flushBuffers[].capacity, uploadBytes
  )

  let uploadBase = flushBuffers[].data.borrow.contents()
  copyToUpload(uploadBase, positionsOffset, ctx.positions.data, positionsBytes)
  copyToUpload(uploadBase, uvsOffset, ctx.uvs.data, uvsBytes)
  copyToUpload(uploadBase, colorsOffset, ctx.colors.data, colorsBytes)
  copyToUpload(
    uploadBase, fillMidColorsOffset, ctx.fillMidColors.data, fillMidColorsBytes
  )
  copyToUpload(
    uploadBase, fillStopColorsOffset, ctx.fillStopColors.data, fillStopColorsBytes
  )
  copyToUpload(uploadBase, sdfParamsOffset, ctx.sdfParams.data, sdfParamsBytes)
  copyToUpload(uploadBase, sdfRadiiOffset, ctx.sdfRadii.data, sdfRadiiBytes)
  copyToUpload(uploadBase, sdfModeOffset, ctx.sdfModeAttr.data, sdfModeBytes)
  copyToUpload(uploadBase, sdfFactorsOffset, ctx.sdfFactors.data, sdfFactorsBytes)
  if useRectMaskPipeline:
    copyToUpload(
      uploadBase, rectMaskParamsOffset, ctx.rectMaskParams.data, rectMaskParamsBytes
    )
    copyToUpload(
      uploadBase, rectMaskRadiiOffset, ctx.rectMaskRadii.data, rectMaskRadiiBytes
    )
    copyToUpload(
      uploadBase, rectMaskMatXOffset, ctx.rectMaskMatX.data, rectMaskMatXBytes
    )
    copyToUpload(
      uploadBase, rectMaskMatYOffset, ctx.rectMaskMatY.data, rectMaskMatYBytes
    )

  let uploadBuffer = flushBuffers[].data.borrow
  setVertexBuffer(enc, uploadBuffer, NSUInteger(positionsOffset), 0)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(uvsOffset), 1)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(colorsOffset), 2)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(sdfParamsOffset), 3)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(sdfRadiiOffset), 4)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(sdfModeOffset), 5)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(sdfFactorsOffset), 6)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(fillMidColorsOffset), 7)
  setVertexBuffer(enc, uploadBuffer, NSUInteger(fillStopColorsOffset), 8)
  if useRectMaskPipeline:
    setVertexBuffer(enc, uploadBuffer, NSUInteger(rectMaskParamsOffset), 9)
    setVertexBuffer(enc, uploadBuffer, NSUInteger(rectMaskRadiiOffset), 10)
    setVertexBuffer(enc, uploadBuffer, NSUInteger(rectMaskMatXOffset), 11)
    setVertexBuffer(enc, uploadBuffer, NSUInteger(rectMaskMatYOffset), 12)

  type VSUniforms = object
    proj: Mat4

  var vsu = VSUniforms(proj: ctx.proj)
  setVertexBytes(
    enc, addr vsu, NSUInteger(sizeof(VSUniforms)), (if useRectMaskPipeline: 13 else: 9)
  )

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
  setFragmentTexture(enc, ctx.backdropTexture.borrow, 2)

  drawIndexedPrimitives(
    enc,
    MTLPrimitiveTypeTriangle,
    NSUInteger(indexCount),
    MTLIndexTypeUInt16,
    ctx.indices.buffer.borrow,
    0,
  )

  ctx.quadCount = 0
  ctx.batchHasRectMask = false

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): MetalContext =
  info "Starting Metal Context",
    atlasSize = atlasSize,
    atlasMargin = atlasMargin,
    maxQuads = maxQuads,
    quadLimit = quadLimit,
    pixelate = pixelate,
    pixelScale = pixelScale
  if maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  withAutoreleasePool:
    result = MetalContext()
    result.atlasSize = atlasSize
    result.initialAtlasSize = atlasSize
    result.atlasMargin = atlasMargin
    result.maxQuads = maxQuads
    result.mat = mat4()
    result.mats = newSeq[Mat4]()
    result.entries = initTable[Hash, Rect]()
    result.atlasEntryMeta = initTable[Hash, AtlasEntryMeta]()
    result.pixelate = pixelate
    result.pixelScale = pixelScale
    result.aaFactor = figbackend.DefaultSdfAaFactor
    result.frameArenas = @[]
    result.activeArena = -1
    result.inFlightFrames = @[]

    result.ensureDeviceAndPipelines()

    result.heights = newSeq[uint16](atlasSize)
    result.atlasTexture.resetRetained(result.createAtlasTexture(atlasSize))
    result.ensureMask0()
    result.ensureImageMessageSubscription()
    result.noteAtlasCreated()

    # Allocate CPU-side arrays.
    result.positions.data = newSeq[float32](2 * maxQuads * 4)
    result.colors.data = newSeq[uint8](4 * maxQuads * 4)
    result.fillMidColors.data = newSeq[uint8](4 * maxQuads * 4)
    result.fillStopColors.data = newSeq[uint8](4 * maxQuads * 4)
    result.uvs.data = newSeq[float32](2 * maxQuads * 4)
    result.sdfParams.data = newSeq[float32](4 * maxQuads * 4)
    result.sdfRadii.data = newSeq[float32](4 * maxQuads * 4)
    result.sdfModeAttr.data = newSeq[SdfModeData](1 * maxQuads * 4)
    result.sdfFactors.data = newSeq[float32](2 * maxQuads * 4)
    result.rectMaskParams.data = newSeq[float32](4 * maxQuads * 4)
    result.rectMaskRadii.data = newSeq[float32](4 * maxQuads * 4)
    result.rectMaskMatX.data = newSeq[float32](4 * maxQuads * 4)
    result.rectMaskMatY.data = newSeq[float32](4 * maxQuads * 4)
    result.rectMaskStack = @[]

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

method atlasEntryMetaPtr*(ctx: MetalContext): var Table[Hash, AtlasEntryMeta] =
  result = ctx.atlasEntryMeta

method atlasSize*(ctx: MetalContext): int =
  ctx.atlasSize

method atlasPackedArea*(ctx: MetalContext): int =
  for height in ctx.heights:
    result += int(height)

method pixelScale*(ctx: MetalContext): float32 =
  ctx.pixelScale

method readPixels*(ctx: MetalContext, frame: Rect, readFront: bool): Image =
  discard readFront
  readPixels(ctx, frame)
