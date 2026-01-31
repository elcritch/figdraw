import std/[hashes, os, strformat, strutils, tables]

import darwin/objc/runtime
import darwin/foundation/[nserror, nsstring]

import pkg/pixie
import pkg/pixie/simd
import pkg/chroma
import pkg/chronicles
import metalx/[cametal, metal]

import ../commons
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

type PassKind = enum
  pkNone
  pkMain
  pkMask
  pkBlit

type SdfModeData = uint16

type Context* = ref object # Metal objects
  device: MTLDevice
  queue: MTLCommandQueue
  commandBuffer: MTLCommandBuffer
  encoder: MTLRenderCommandEncoder
  passKind: PassKind

  pipelineMain: MTLRenderPipelineState
  pipelineMask: MTLRenderPipelineState
  pipelineBlit: MTLRenderPipelineState

  # Optional presentation target.
  # Windowing code owns attaching/sizing this layer.
  presentLayer*: CAMetalLayer

  # Render targets
  offscreenTexture: MTLTexture
  atlasTexture: MTLTexture
  maskTextures: seq[MTLTexture]
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
  indices: tuple[buffer: MTLBuffer, data: seq[uint16]]
  positions: tuple[buffer: MTLBuffer, data: seq[float32]]
  colors: tuple[buffer: MTLBuffer, data: seq[uint8]]
  uvs: tuple[buffer: MTLBuffer, data: seq[float32]]
  sdfParams: tuple[buffer: MTLBuffer, data: seq[float32]]
  sdfRadii: tuple[buffer: MTLBuffer, data: seq[float32]]
  sdfModeAttr: tuple[buffer: MTLBuffer, data: seq[SdfModeData]]
  sdfFactors: tuple[buffer: MTLBuffer, data: seq[float32]]

  # SDF shader uniform (global)
  aaFactor: float32

  # For screenshot readback.
  lastCommitted: MTLCommandBuffer

proc flush(ctx: Context, maskTextureRead: int = ctx.maskTextureWrite)

proc ensureDeviceAndPipelines(ctx: Context)

proc metalDevice*(ctx: Context): MTLDevice =
  ## Exposes the MTLDevice for windowing code that needs to create a CAMetalLayer.
  if ctx.device.isNil:
    ctx.ensureDeviceAndPipelines()
  result = ctx.device

proc toKey*(h: Hash): Hash =
  h

proc hasImage*(ctx: Context, key: Hash): bool =
  key in ctx.entries

proc mtlRegion2D(x, y, w, h: int): MTLRegion =
  result.origin = MTLOrigin(x: NSUInteger(x), y: NSUInteger(y), z: 0)
  result.size = MTLSize(width: NSUInteger(w), height: NSUInteger(h), depth: 1)

proc newTexture2D(
    ctx: Context,
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
  result = ctx.device.newTextureWithDescriptor(desc)

proc updateSubImage(ctx: Context, texture: MTLTexture, x, y: int, image: Image) =
  # Pixie Image is RGBA; our atlas is RGBA8.
  let region = mtlRegion2D(x, y, image.width, image.height)
  texture.replaceRegion(region, 0, image.data[0].addr, NSUInteger(image.width * 4))

proc createAtlasTexture(ctx: Context, size: int): MTLTexture =
  # No mipmaps for now; keep it simple and deterministic.
  result = ctx.newTexture2D(
    pixelFormat = MTLPixelFormatRGBA8Unorm,
    width = size,
    height = size,
    usage = MTLTextureUsageShaderRead,
  )

proc createMaskTexture(ctx: Context, width, height: int): MTLTexture =
  result = ctx.newTexture2D(
    pixelFormat = MTLPixelFormatR8Unorm,
    width = width,
    height = height,
    usage = MTLTextureUsage(
      cast[NSUInteger](MTLTextureUsageShaderRead) or
        cast[NSUInteger](MTLTextureUsageRenderTarget)
    ),
  )

proc ensureMask0(ctx: Context) =
  if ctx.maskTextures.len > 0:
    return
  let tex = ctx.createMaskTexture(1, 1)
  var white = 255'u8
  tex.replaceRegion(mtlRegion2D(0, 0, 1, 1), 0, addr white, 1)
  ctx.maskTextures.add(tex)

proc ensureOffscreen(ctx: Context, frameSize: Vec2) =
  let w = max(1, frameSize.x.int)
  let h = max(1, frameSize.y.int)
  if not ctx.offscreenTexture.isNil:
    # If size matches, keep existing.
    if ctx.offscreenTexture.width.int == w and ctx.offscreenTexture.height.int == h:
      return
  ctx.offscreenTexture = ctx.newTexture2D(
    pixelFormat = MTLPixelFormatBGRA8Unorm,
    width = w,
    height = h,
    usage = MTLTextureUsage(
      cast[NSUInteger](MTLTextureUsageShaderRead) or
        cast[NSUInteger](MTLTextureUsageRenderTarget)
    ),
  )

proc endEncoder(ctx: Context) =
  if not ctx.encoder.isNil:
    endEncoding(ctx.encoder)
    ctx.encoder = nil
    ctx.passKind = pkNone

proc beginPass(
    ctx: Context,
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
  ctx.encoder = renderCommandEncoderWithDescriptor(ctx.commandBuffer, pass)
  ctx.passKind = kind

proc ensureMainPass(ctx: Context, clear: bool, clearColor: MTLClearColor) =
  if ctx.passKind == pkMain and not ctx.encoder.isNil:
    return
  ctx.beginPass(pkMain, ctx.offscreenTexture, clear, clearColor)

proc ensureMaskPass(ctx: Context, clear: bool, clearColor: MTLClearColor) =
  if ctx.passKind == pkMask and not ctx.encoder.isNil:
    return
  ctx.beginPass(pkMask, ctx.maskTextures[ctx.maskTextureWrite], clear, clearColor)

proc ensureDeviceAndPipelines(ctx: Context) =
  if not ctx.device.isNil and not ctx.queue.isNil and not ctx.pipelineMain.isNil and
      not ctx.pipelineMask.isNil and not ctx.pipelineBlit.isNil:
    return

  ctx.device = MTLCreateSystemDefaultDevice()
  if ctx.device.isNil:
    raise newException(ValueError, "Metal device not available")
  ctx.queue = newCommandQueue(ctx.device)
  if ctx.queue.isNil:
    raise newException(ValueError, "Failed to create Metal command queue")

  let shaderSource = metalShaderSource

  var err: NSError
  let library = newLibraryWithSource(
    ctx.device,
    NSString.withUTF8String(cstring(shaderSource)),
    MTLCompileOptions(nil),
    addr err,
  )
  if library.isNil:
    if not err.isNil:
      error "Failed to compile Metal shaders", error = $err
    raise newException(ValueError, "Failed to compile Metal shaders")

  let vsMain = newFunctionWithName(library, NSString.withUTF8String(cstring("vs_main")))
  let fsMain = newFunctionWithName(library, NSString.withUTF8String(cstring("fs_main")))
  let fsMask = newFunctionWithName(library, NSString.withUTF8String(cstring("fs_mask")))
  let vsBlit = newFunctionWithName(library, NSString.withUTF8String(cstring("vs_blit")))
  let fsBlit = newFunctionWithName(library, NSString.withUTF8String(cstring("fs_blit")))
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
    let pd = MTLRenderPipelineDescriptor.alloc().init()
    setVertexFunction(pd, vsMain)
    setFragmentFunction(pd, fsMain)
    let ca0 = objectAtIndexedSubscript(colorAttachments(pd), 0)
    setPixelFormat(ca0, MTLPixelFormatBGRA8Unorm)
    configureBlend(ca0)
    ctx.pipelineMain = newRenderPipelineStateWithDescriptor(ctx.device, pd, addr err)
    if ctx.pipelineMain.isNil:
      if not err.isNil:
        error "Failed to create Metal main pipeline", error = $err
      raise newException(ValueError, "Failed to create Metal main pipeline")

  # Mask pipeline (R8).
  block:
    let pd = MTLRenderPipelineDescriptor.alloc().init()
    setVertexFunction(pd, vsMain)
    setFragmentFunction(pd, fsMask)
    let ca0 = objectAtIndexedSubscript(colorAttachments(pd), 0)
    setPixelFormat(ca0, MTLPixelFormatR8Unorm)
    configureBlend(ca0)
    ctx.pipelineMask = newRenderPipelineStateWithDescriptor(ctx.device, pd, addr err)
    if ctx.pipelineMask.isNil:
      if not err.isNil:
        error "Failed to create Metal mask pipeline", error = $err
      raise newException(ValueError, "Failed to create Metal mask pipeline")

  # Blit pipeline (drawable BGRA8, no blending).
  block:
    let pd = MTLRenderPipelineDescriptor.alloc().init()
    setVertexFunction(pd, vsBlit)
    setFragmentFunction(pd, fsBlit)
    let ca0 = objectAtIndexedSubscript(colorAttachments(pd), 0)
    setPixelFormat(ca0, MTLPixelFormatBGRA8Unorm)
    ctx.pipelineBlit = newRenderPipelineStateWithDescriptor(ctx.device, pd, addr err)
    if ctx.pipelineBlit.isNil:
      if not err.isNil:
        error "Failed to create Metal blit pipeline", error = $err
      raise newException(ValueError, "Failed to create Metal blit pipeline")

proc upload(ctx: Context) =
  let vertexCount = ctx.quadCount * 4
  if vertexCount <= 0:
    return

  template copySeqToBuf(buf: MTLBuffer, src: untyped, bytes: int) =
    let dst = buf.contents()
    if dst.isNil:
      raise newException(ValueError, "MTLBuffer.contents() returned nil")
    copyMem(dst, src[0].addr, bytes)

  copySeqToBuf(
    ctx.positions.buffer, ctx.positions.data, vertexCount * 2 * sizeof(float32)
  )
  copySeqToBuf(ctx.uvs.buffer, ctx.uvs.data, vertexCount * 2 * sizeof(float32))
  copySeqToBuf(ctx.colors.buffer, ctx.colors.data, vertexCount * 4 * sizeof(uint8))
  copySeqToBuf(
    ctx.sdfParams.buffer, ctx.sdfParams.data, vertexCount * 4 * sizeof(float32)
  )
  copySeqToBuf(
    ctx.sdfRadii.buffer, ctx.sdfRadii.data, vertexCount * 4 * sizeof(float32)
  )
  copySeqToBuf(
    ctx.sdfModeAttr.buffer, ctx.sdfModeAttr.data, vertexCount * sizeof(SdfModeData)
  )
  copySeqToBuf(
    ctx.sdfFactors.buffer, ctx.sdfFactors.data, vertexCount * 2 * sizeof(float32)
  )

proc grow(ctx: Context) =
  ctx.flush()
  ctx.atlasSize = ctx.atlasSize * 2
  info "grow atlasSize ", atlasSize = ctx.atlasSize
  ctx.heights.setLen(ctx.atlasSize)
  ctx.atlasTexture = ctx.createAtlasTexture(ctx.atlasSize)
  ctx.entries.clear()

proc findEmptyRect(ctx: Context, width, height: int): Rect =
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

proc putImage*(ctx: Context, path: Hash, image: Image) =
  let rect = ctx.findEmptyRect(image.width, image.height)
  ctx.entries[path] = rect / float(ctx.atlasSize)
  ctx.updateSubImage(ctx.atlasTexture, int(rect.x), int(rect.y), image)

proc addImage*(ctx: Context, key: Hash, image: Image) =
  ctx.putImage(key, image)

proc updateImage*(ctx: Context, path: Hash, image: Image) =
  let rect = ctx.entries[path]
  assert rect.w == image.width.float / float(ctx.atlasSize)
  assert rect.h == image.height.float / float(ctx.atlasSize)
  ctx.updateSubImage(
    ctx.atlasTexture,
    int(rect.x * ctx.atlasSize.float),
    int(rect.y * ctx.atlasSize.float),
    image,
  )

proc logFlippy(flippy: Flippy, file: string) =
  debug "putFlippy file",
    fwidth = $flippy.width, fheight = $flippy.height, flippyPath = file

proc putFlippy*(ctx: Context, path: Hash, flippy: Flippy) =
  # Metal backend currently uploads only mip 0.
  logFlippy(flippy, $path)
  if flippy.mipmaps.len == 0:
    return
  let mip0 = flippy.mipmaps[0]
  ctx.putImage(path, mip0)

proc putImage*(ctx: Context, imgObj: ImgObj) =
  case imgObj.kind
  of FlippyImg:
    ctx.putFlippy(imgObj.id.Hash, imgObj.flippy)
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)

proc checkBatch(ctx: Context) =
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
    ctx: Context,
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

proc drawUvRectAtlasSdf(
    ctx: Context,
    at, to: Vec2,
    uvAt, uvTo: Vec2,
    color: Color,
    mode: SdfMode,
    factors: Vec2,
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

  let zero4 =
    if mode == sdfModeMsdf or mode == sdfModeMtsdf:
      vec4(ctx.atlasSize.float32, 0.0'f32, 0.0'f32, 0.0'f32)
    else:
      vec4(0.0'f32)
  ctx.sdfParams.data.setVert4(offset + 0, zero4)
  ctx.sdfParams.data.setVert4(offset + 1, zero4)
  ctx.sdfParams.data.setVert4(offset + 2, zero4)
  ctx.sdfParams.data.setVert4(offset + 3, zero4)

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

proc drawMsdfImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
) =
  let rect = ctx.entries[imageId]
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = rect.xy,
    uvTo = rect.xy + rect.wh,
    color = color,
    mode = sdfModeMsdf,
    factors = vec2(pxRange, sdThreshold),
  )

proc drawMtsdfImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32 = 0.5,
) =
  let rect = ctx.entries[imageId]
  ctx.drawUvRectAtlasSdf(
    at = pos,
    to = pos + size,
    uvAt = rect.xy,
    uvTo = rect.xy + rect.wh,
    color = color,
    mode = sdfModeMtsdf,
    factors = vec2(pxRange, sdThreshold),
  )

proc setSdfGlobals*(ctx: Context, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.aaFactor = aaFactor

proc drawUvRect(ctx: Context, at, to: Vec2, uvAt, uvTo: Vec2, color: Color) =
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

proc drawUvRect(ctx: Context, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc getImageRect(ctx: Context, imageId: Hash): Rect =
  ctx.entries[imageId]

proc drawImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  let rect = ctx.getImageRect(imageId)
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, color)

proc drawImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  let rect = ctx.getImageRect(imageId)
  ctx.drawUvRect(pos, pos + size, rect.xy, rect.xy + rect.wh, color)

proc drawImageAdj*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  let
    rect = ctx.getImageRect(imageId)
    adj = vec2(2 / ctx.atlasSize.float32)
  ctx.drawUvRect(pos, pos + size, rect.xy + adj, rect.xy + rect.wh - adj, color)

proc drawSprite*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  let
    rect = ctx.getImageRect(imageId)
    wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos - wh / 2, pos + wh / 2, rect.xy, rect.xy + rect.wh, color)

proc drawSprite*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  let rect = ctx.getImageRect(imageId)
  ctx.drawUvRect(pos - size / 2, pos + size / 2, rect.xy, rect.xy + rect.wh, color)

proc drawRect*(ctx: Context, rect: Rect, color: Color) =
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

proc drawRoundedRectSdf*(
    ctx: Context,
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

proc line*(ctx: Context, a: Vec2, b: Vec2, weight: float32, color: Color) =
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

proc linePolygon*(ctx: Context, poly: seq[Vec2], weight: float32, color: Color) =
  for i in 0 ..< poly.len:
    ctx.line(poly[i], poly[(i + 1) mod poly.len], weight, color)

proc beginMask*(ctx: Context) =
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginMask has already been called."
  # Flush any pending main-pass quads before switching into mask mode.
  ctx.flush(ctx.maskTextureWrite)
  ctx.maskBegun = true

  inc ctx.maskTextureWrite
  if ctx.maskTextureWrite >= ctx.maskTextures.len:
    ctx.maskTextures.add(
      ctx.createMaskTexture(ctx.frameSize.x.int, ctx.frameSize.y.int)
    )
  else:
    # Resize existing mask textures (slot 0 is the 1x1 base).
    if ctx.maskTextureWrite > 0:
      ctx.maskTextures[ctx.maskTextureWrite] =
        ctx.createMaskTexture(ctx.frameSize.x.int, ctx.frameSize.y.int)

  ctx.ensureMaskPass(
    clear = true,
    clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
  )

proc endMask*(ctx: Context) =
  assert ctx.maskBegun == true, "ctx.maskBegun has not been called."
  # Flush any remaining quads for this mask level while the mask pipeline is active.
  ctx.flush(ctx.maskTextureWrite - 1)
  ctx.maskBegun = false

  ctx.ensureMainPass(
    clear = false,
    clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0),
  )

proc popMask*(ctx: Context) =
  ctx.flush()
  dec ctx.maskTextureWrite

proc beginFrame*(ctx: Context, frameSize: Vec2, proj: Mat4, clearMain = false) =
  assert ctx.frameBegun == false, "ctx.beginFrame has already been called."
  ctx.frameBegun = true

  ctx.ensureDeviceAndPipelines()
  ctx.ensureMask0()

  ctx.maskBegun = false
  ctx.maskTextureWrite = 0

  ctx.proj = proj
  ctx.frameSize = frameSize

  ctx.ensureOffscreen(frameSize)
  # Resize any existing mask textures > 0.
  for i in 1 ..< ctx.maskTextures.len:
    ctx.maskTextures[i] = ctx.createMaskTexture(frameSize.x.int, frameSize.y.int)

  ctx.commandBuffer = commandBuffer(ctx.queue)
  if ctx.commandBuffer.isNil:
    raise newException(ValueError, "Failed to create Metal command buffer")
  ctx.lastCommitted = ctx.commandBuffer

  # Always start in main pass.
  ctx.ensureMainPass(
    clear = clearMain,
    clearColor = MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0),
  )

proc beginFrame*(ctx: Context, frameSize: Vec2, clearMain = false) =
  beginFrame(
    ctx,
    frameSize,
    ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0),
    clearMain = clearMain,
  )

proc endFrame*(ctx: Context) =
  assert ctx.frameBegun == true, "ctx.beginFrame was not called first."
  assert ctx.maskTextureWrite == 0, "Not all masks have been popped."
  ctx.frameBegun = false

  ctx.flush()
  ctx.endEncoder()

  if not ctx.presentLayer.isNil:
    let drawable = ctx.presentLayer.nextDrawable()
    if not drawable.isNil:
      let pass = MTLRenderPassDescriptor.renderPassDescriptor()
      let att0 = objectAtIndexedSubscript(colorAttachments(pass), 0)
      setTexture(att0, texture(drawable))
      setLoadAction(att0, MTLLoadActionClear)
      setStoreAction(att0, MTLStoreActionStore)
      setClearColor(att0, MTLClearColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
      let enc = renderCommandEncoderWithDescriptor(ctx.commandBuffer, pass)
      if not enc.isNil:
        setRenderPipelineState(enc, ctx.pipelineBlit)
        setFragmentTexture(enc, ctx.offscreenTexture, 0)
        drawPrimitives(enc, MTLPrimitiveTypeTriangle, 0, 3)
        endEncoding(enc)
      presentDrawable(ctx.commandBuffer, cast[MTLDrawable](drawable))

  commit(ctx.commandBuffer)
  ctx.lastCommitted = ctx.commandBuffer

proc translate*(ctx: Context, v: Vec2) =
  ctx.mat = ctx.mat * translate(vec3(v))

proc rotate*(ctx: Context, angle: float32) =
  ctx.mat = ctx.mat * rotateZ(angle)

proc scale*(ctx: Context, s: float32) =
  ctx.mat = ctx.mat * scale(vec3(s))

proc scale*(ctx: Context, s: Vec2) =
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))

proc saveTransform*(ctx: Context) =
  ctx.mats.add ctx.mat

proc restoreTransform*(ctx: Context) =
  ctx.mat = ctx.mats.pop()

proc clearTransform*(ctx: Context) =
  ctx.mat = mat4()
  ctx.mats.setLen(0)

proc fromScreen*(ctx: Context, windowFrame: Vec2, v: Vec2): Vec2 =
  (ctx.mat.inverse() * vec3(v.x, windowFrame.y - v.y, 0)).xy

proc toScreen*(ctx: Context, windowFrame: Vec2, v: Vec2): Vec2 =
  result = (ctx.mat * vec3(v.x, v.y, 1)).xy
  result.y = -result.y + windowFrame.y

proc setPresentLayer*(ctx: Context, layer: CAMetalLayer) =
  ## Optional: set a CAMetalLayer to present the offscreen result into.
  ## The caller is responsible for attaching/sizing/configuring the layer.
  ctx.presentLayer = layer

proc readPixels*(ctx: Context, frame: Rect = rect(0, 0, 0, 0)): Image =
  if ctx.lastCommitted.isNil:
    raise newException(ValueError, "No Metal frame has been committed yet")
  waitUntilCompleted(ctx.lastCommitted)

  let
    texW = ctx.offscreenTexture.width.int
    texH = ctx.offscreenTexture.height.int

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
  ctx.offscreenTexture.getBytes(
    tmp[0].addr, NSUInteger(w * 4), mtlRegion2D(x, y, w, h), 0
  )

  # Offscreen is BGRA8; Pixie expects RGBA.
  for i in 0 ..< w * h:
    let bi = i * 4
    result.data[i] = rgbx(tmp[bi + 2], tmp[bi + 1], tmp[bi + 0], tmp[bi + 3])

proc flush(ctx: Context, maskTextureRead: int = ctx.maskTextureWrite) =
  if ctx.quadCount == 0:
    return

  ctx.upload()

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

  setRenderPipelineState(enc, if ctx.maskBegun: ctx.pipelineMask else: ctx.pipelineMain)

  setVertexBuffer(enc, ctx.positions.buffer, 0, 0)
  setVertexBuffer(enc, ctx.uvs.buffer, 0, 1)
  setVertexBuffer(enc, ctx.colors.buffer, 0, 2)
  setVertexBuffer(enc, ctx.sdfParams.buffer, 0, 3)
  setVertexBuffer(enc, ctx.sdfRadii.buffer, 0, 4)
  setVertexBuffer(enc, ctx.sdfModeAttr.buffer, 0, 5)
  setVertexBuffer(enc, ctx.sdfFactors.buffer, 0, 6)

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

  setFragmentTexture(enc, ctx.atlasTexture, 0)
  let maskIndex = clamp(maskTextureRead, 0, ctx.maskTextures.high)
  setFragmentTexture(enc, ctx.maskTextures[maskIndex], 1)

  drawIndexedPrimitives(
    enc,
    MTLPrimitiveTypeTriangle,
    NSUInteger(indexCount),
    MTLIndexTypeUInt16,
    ctx.indices.buffer,
    0,
  )

  ctx.quadCount = 0

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): Context =
  if maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  result = Context()
  result.atlasSize = atlasSize
  result.atlasMargin = atlasMargin
  result.maxQuads = maxQuads
  result.mat = mat4()
  result.mats = newSeq[Mat4]()
  result.pixelate = pixelate
  result.pixelScale = pixelScale
  result.aaFactor = 1.2'f32

  result.ensureDeviceAndPipelines()

  result.heights = newSeq[uint16](atlasSize)
  result.atlasTexture = result.createAtlasTexture(atlasSize)
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
  result.positions.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.positions.data.len * sizeof(float32)),
    MTLResourceOptions(0),
  )
  result.colors.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.colors.data.len * sizeof(uint8)),
    MTLResourceOptions(0),
  )
  result.uvs.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.uvs.data.len * sizeof(float32)),
    MTLResourceOptions(0),
  )
  result.sdfParams.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.sdfParams.data.len * sizeof(float32)),
    MTLResourceOptions(0),
  )
  result.sdfRadii.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.sdfRadii.data.len * sizeof(float32)),
    MTLResourceOptions(0),
  )
  result.sdfModeAttr.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.sdfModeAttr.data.len * sizeof(SdfModeData)),
    MTLResourceOptions(0),
  )
  result.sdfFactors.buffer = newBufferWithLength(
    result.device,
    NSUInteger(result.sdfFactors.data.len * sizeof(float32)),
    MTLResourceOptions(0),
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

  result.indices.buffer = newBufferWithBytes(
    result.device,
    result.indices.data[0].addr,
    NSUInteger(result.indices.data.len * sizeof(uint16)),
    MTLResourceOptions(0),
  )
