import
  buffers, chroma, pixie, hashes, opengl, os, shaders, strformat, strutils, tables,
  textures, times

## Copied from Fidget backend, copyright from @treeform applies

import pixie/simd

import pkg/chronicles

import ../commons
import ../common/formatflippy
import ../fignodes
import ../utils/drawextras
import ../utils/drawboxes
import ../utils/drawshadows

export drawextras

logScope:
  scope = "opengl"

proc round*(v: Vec2): Vec2 =
  vec2(round(v.x), round(v.y))

const quadLimit = 10_921

when defined(emscripten):
  type SdfModeData = float32
else:
  type SdfModeData = uint16

type Context* = ref object
  mainShader, maskShader, activeShader: Shader
  atlasTexture: Texture
  maskTextureWrite: int       ## Index into max textures for writing.
  maskTextures: seq[Texture]  ## Masks array for pushing and popping.
  atlasSize: int              ## Size x size dimensions of the atlas
  atlasMargin: int            ## Default margin between images
  quadCount: int              ## Number of quads drawn so far
  maxQuads: int               ## Max quads to draw before issuing an OpenGL call
  mat*: Mat4                  ## Current matrix
  mats: seq[Mat4]             ## Matrix stack
  entries*: Table[Hash, Rect] ## Mapping of image name to atlas UV position
  heights: seq[uint16]        ## Height map of the free space in the atlas
  proj*: Mat4
  frameSize: Vec2             ## Dimensions of the window frame
  vertexArrayId, maskFramebufferId: GLuint
  frameBegun, maskBegun: bool
  pixelate*: bool             ## Makes texture look pixelated, like a pixel game.
  pixelScale*: float32        ## Multiple scaling factor.

  # Buffer data for OpenGL
  indices: tuple[buffer: Buffer, data: seq[uint16]]
  positions: tuple[buffer: Buffer, data: seq[float32]]
  colors: tuple[buffer: Buffer, data: seq[uint8]]
  uvs: tuple[buffer: Buffer, data: seq[float32]]
  sdfParams: tuple[buffer: Buffer, data: seq[float32]]
    ## Vec4: (halfExtents.xy, strokeWidth, unused)
  sdfRadii: tuple[buffer: Buffer, data: seq[float32]]
    ## Vec4: (topRight, bottomRight, topLeft, bottomLeft)
  sdfModeAttr: tuple[buffer: Buffer, data: seq[SdfModeData]] ## SDFMode value
  sdfFactors: tuple[buffer: Buffer, data: seq[float32]] ## Vec2: (factor, spread)

  # SDF shader uniforms (global)
  aaFactor: float32

proc flush(ctx: Context, maskTextureRead: int = ctx.maskTextureWrite)

proc toKey*(h: Hash): Hash =
  h

proc hasImage*(ctx: Context, key: Hash): bool =
  key in ctx.entries

proc upload(ctx: Context) =
  ## When buffers change, uploads them to GPU.
  ctx.positions.buffer.count = ctx.quadCount * 4
  ctx.colors.buffer.count = ctx.quadCount * 4
  ctx.uvs.buffer.count = ctx.quadCount * 4
  ctx.indices.buffer.count = ctx.quadCount * 6
  bindBufferData(ctx.positions.buffer.addr, ctx.positions.data[0].addr)
  bindBufferData(ctx.colors.buffer.addr, ctx.colors.data[0].addr)
  bindBufferData(ctx.uvs.buffer.addr, ctx.uvs.data[0].addr)
  ctx.sdfParams.buffer.count = ctx.quadCount * 4
  ctx.sdfRadii.buffer.count = ctx.quadCount * 4
  ctx.sdfModeAttr.buffer.count = ctx.quadCount * 4
  ctx.sdfFactors.buffer.count = ctx.quadCount * 4
  bindBufferData(ctx.sdfParams.buffer.addr, ctx.sdfParams.data[0].addr)
  bindBufferData(ctx.sdfRadii.buffer.addr, ctx.sdfRadii.data[0].addr)
  bindBufferData(ctx.sdfModeAttr.buffer.addr, ctx.sdfModeAttr.data[0].addr)
  bindBufferData(ctx.sdfFactors.buffer.addr, ctx.sdfFactors.data[0].addr)

proc setUpMaskFramebuffer(ctx: Context) =
  glBindFramebuffer(GL_FRAMEBUFFER, ctx.maskFramebufferId)
  glFramebufferTexture2D(
    GL_FRAMEBUFFER,
    GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D,
    ctx.maskTextures[ctx.maskTextureWrite].textureId,
    0,
  )

proc createAtlasTexture(ctx: Context, size: int): Texture =
  result.width = size.GLint
  result.height = size.GLint
  result.componentType = GL_UNSIGNED_BYTE
  result.format = GL_RGBA
  result.internalFormat = GL_RGBA8
  result.genMipmap = true
  result.minFilter = minLinearMipmapLinear
  if ctx.pixelate:
    result.magFilter = magNearest
  else:
    result.magFilter = magLinear
  bindTextureData(result.addr, nil)

proc addMaskTexture(ctx: Context, frameSize = vec2(1, 1)) =
  # Must be >0 for framebuffer creation below
  # Set to real value in beginFrame
  var maskTexture = Texture()
  maskTexture.width = frameSize.x.int32
  maskTexture.height = frameSize.y.int32
  maskTexture.componentType = GL_UNSIGNED_BYTE
  maskTexture.format = GL_RGBA
  when defined(emscripten):
    maskTexture.internalFormat = GL_RGBA8
  else:
    maskTexture.internalFormat = GL_R8
  maskTexture.minFilter = minLinear
  if ctx.pixelate:
    maskTexture.magFilter = magNearest
  else:
    maskTexture.magFilter = magLinear
  bindTextureData(maskTexture.addr, nil)
  ctx.maskTextures.add(maskTexture)

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): Context =
  ## Creates a new context.
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

  result.heights = newSeq[uint16](atlasSize)
  result.atlasTexture = result.createAtlasTexture(atlasSize)

  result.addMaskTexture()

  when defined(emscripten) or defined(useOpenGlEs):
    result.maskShader =
      newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/mask.frag")
    result.mainShader =
      newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/atlas.frag")
  else:
    try:
      result.maskShader = newShaderStatic("glsl/atlas.vert", "glsl/mask.frag")
      result.mainShader = newShaderStatic("glsl/atlas.vert", "glsl/atlas.frag")
    except ShaderCompilationError:
      info "OpenGL 3.30 failed, trying GLSL ES fallback"
      result.maskShader =
        newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/mask.frag")
      result.mainShader =
        newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/atlas.frag")

  result.positions.buffer.componentType = cGL_FLOAT
  result.positions.buffer.kind = bkVEC2
  result.positions.buffer.target = GL_ARRAY_BUFFER
  result.positions.buffer.usage = GL_STREAM_DRAW
  result.positions.data =
    newSeq[float32](result.positions.buffer.kind.componentCount() * maxQuads * 4)

  result.colors.buffer.componentType = GL_UNSIGNED_BYTE
  result.colors.buffer.kind = bkVEC4
  result.colors.buffer.target = GL_ARRAY_BUFFER
  result.colors.buffer.normalized = true
  result.colors.buffer.usage = GL_STREAM_DRAW
  result.colors.data =
    newSeq[uint8](result.colors.buffer.kind.componentCount() * maxQuads * 4)

  result.uvs.buffer.componentType = cGL_FLOAT
  result.uvs.buffer.kind = bkVEC2
  result.uvs.buffer.target = GL_ARRAY_BUFFER
  result.uvs.buffer.usage = GL_STREAM_DRAW
  result.uvs.data =
    newSeq[float32](result.uvs.buffer.kind.componentCount() * maxQuads * 4)

  result.sdfParams.buffer.componentType = cGL_FLOAT
  result.sdfParams.buffer.kind = bkVEC4
  result.sdfParams.buffer.target = GL_ARRAY_BUFFER
  result.sdfParams.buffer.usage = GL_STREAM_DRAW
  result.sdfParams.data =
    newSeq[float32](result.sdfParams.buffer.kind.componentCount() * maxQuads * 4)

  result.sdfRadii.buffer.componentType = cGL_FLOAT
  result.sdfRadii.buffer.kind = bkVEC4
  result.sdfRadii.buffer.target = GL_ARRAY_BUFFER
  result.sdfRadii.buffer.usage = GL_STREAM_DRAW
  result.sdfRadii.data =
    newSeq[float32](result.sdfRadii.buffer.kind.componentCount() * maxQuads * 4)

  when defined(emscripten):
    result.sdfModeAttr.buffer.componentType = cGL_FLOAT
  else:
    result.sdfModeAttr.buffer.componentType = GL_UNSIGNED_SHORT
  result.sdfModeAttr.buffer.kind = bkSCALAR
  result.sdfModeAttr.buffer.target = GL_ARRAY_BUFFER
  result.sdfModeAttr.buffer.usage = GL_STREAM_DRAW
  result.sdfModeAttr.data =
    newSeq[SdfModeData](result.sdfModeAttr.buffer.kind.componentCount() *
        maxQuads * 4)

  result.sdfFactors.buffer.componentType = cGL_FLOAT
  result.sdfFactors.buffer.kind = bkVEC2
  result.sdfFactors.buffer.target = GL_ARRAY_BUFFER
  result.sdfFactors.buffer.usage = GL_STREAM_DRAW
  result.sdfFactors.data =
    newSeq[float32](result.sdfFactors.buffer.kind.componentCount() * maxQuads * 4)

  result.indices.buffer.componentType = GL_UNSIGNED_SHORT
  result.indices.buffer.kind = bkSCALAR
  result.indices.buffer.target = GL_ELEMENT_ARRAY_BUFFER
  result.indices.buffer.usage = GL_STATIC_DRAW
  result.indices.buffer.count = maxQuads * 6

  for i in 0 ..< maxQuads:
    let offset = i * 4
    result.indices.data.add(
      [
        (offset + 3).uint16,
        (offset + 0).uint16,
        (offset + 1).uint16,
        (offset + 2).uint16,
        (offset + 3).uint16,
        (offset + 1).uint16,
      ]
    )

  # Indices are only uploaded once
  bindBufferData(result.indices.buffer.addr, result.indices.data[0].addr)

  result.upload()

  result.activeShader = result.mainShader

  glGenVertexArrays(1, result.vertexArrayId.addr)
  glBindVertexArray(result.vertexArrayId)

  # Main shader (atlas + SDF).
  result.mainShader.bindAttrib("vertexPos", result.positions.buffer)
  result.mainShader.bindAttrib("vertexColor", result.colors.buffer)
  result.mainShader.bindAttrib("vertexUv", result.uvs.buffer)
  result.mainShader.bindAttrib("vertexSdfParams", result.sdfParams.buffer)
  result.mainShader.bindAttrib("vertexSdfRadii", result.sdfRadii.buffer)
  result.mainShader.bindAttrib("vertexSdfMode", result.sdfModeAttr.buffer)
  result.mainShader.bindAttrib("vertexSdfFactors", result.sdfFactors.buffer)

  # Mask shader.
  result.maskShader.bindAttrib("vertexPos", result.positions.buffer)
  result.maskShader.bindAttrib("vertexColor", result.colors.buffer)
  result.maskShader.bindAttrib("vertexUv", result.uvs.buffer)
  result.maskShader.bindAttrib("vertexSdfParams", result.sdfParams.buffer)
  result.maskShader.bindAttrib("vertexSdfRadii", result.sdfRadii.buffer)
  result.maskShader.bindAttrib("vertexSdfMode", result.sdfModeAttr.buffer)

  # Create mask framebuffer
  glGenFramebuffers(1, result.maskFramebufferId.addr)
  result.setUpMaskFramebuffer()

  let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
  if status != GL_FRAMEBUFFER_COMPLETE:
    quit(&"Something wrong with mask framebuffer: {toHex(status.int32, 4)}")

  glBindFramebuffer(GL_FRAMEBUFFER, 0)

func `[]=`(t: var Table[Hash, Rect], key: string, rect: Rect) =
  t[hash(key)] = rect

func `[]`(t: var Table[Hash, Rect], key: string): Rect =
  t[hash(key)]

proc hash(v: Vec2): Hash =
  hash((v.x, v.y))

proc hash(radii: array[DirectionCorners, float32]): Hash =
  for r in radii:
    result = result !& hash(r)

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
      # found low point, is it consecutive?
      var fit = true
      for j in 0 .. imgWidth:
        if i + j >= ctx.atlasSize:
          fit = false
          break
        if int(ctx.heights[i + j]) > v:
          fit = false
          break
      if fit:
        # found!
        lowest = v
        at = i

  if lowest + imgHeight > ctx.atlasSize:
    #raise newException(Exception, "Context Atlas is full")
    ctx.grow()
    return ctx.findEmptyRect(width, height)

  for j in at .. at + imgWidth - 1:
    ctx.heights[j] = uint16(lowest + imgHeight + ctx.atlasMargin * 2)

  var rect = rect(
    float32(at + ctx.atlasMargin),
    float32(lowest + ctx.atlasMargin),
    float32(width),
    float32(height),
  )

  return rect

proc putImage*(ctx: Context, path: Hash, image: Image) =
  # Reminder: This does not set mipmaps (used for text, should it?)
  let rect = ctx.findEmptyRect(image.width, image.height)
  ctx.entries[path] = rect / float(ctx.atlasSize)
  updateSubImage(ctx.atlasTexture, int(rect.x), int(rect.y), image)

proc addImage*(ctx: Context, key: Hash, image: Image) =
  ctx.putImage(key, image)

proc updateImage*(ctx: Context, path: Hash, image: Image) =
  ## Updates an image that was put there with putImage.
  ## Useful for things like video.
  ## * Must be the same size.
  ## * This does not set mipmaps.
  let rect = ctx.entries[path]
  assert rect.w == image.width.float / float(ctx.atlasSize)
  assert rect.h == image.height.float / float(ctx.atlasSize)
  updateSubImage(
    ctx.atlasTexture,
    int(rect.x * ctx.atlasSize.float),
    int(rect.y * ctx.atlasSize.float),
    image,
  )

proc logFlippy(flippy: Flippy, file: string) =
  debug "putFlippy file",
    fwidth = $flippy.width, fheight = $flippy.height, flippyPath = file

proc putFlippy*(ctx: Context, path: Hash, flippy: Flippy) =
  logFlippy(flippy, $path)
  let rect = ctx.findEmptyRect(flippy.width, flippy.height)
  ctx.entries[path] = rect / float(ctx.atlasSize)
  var
    x = int(rect.x)
    y = int(rect.y)
  for level, mip in flippy.mipmaps:
    updateSubImage(ctx.atlasTexture, x, y, mip, level)
    x = x div 2
    y = y div 2

proc putImage*(ctx: Context, imgObj: ImgObj) =
  ## puts an ImgObj wrapper with either a flippy or image format
  case imgObj.kind:
  of FlippyImg:
    ctx.putFlippy(imgObj.id.Hash, imgObj.flippy)
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)

proc flush(ctx: Context, maskTextureRead: int = ctx.maskTextureWrite) =
  ## Flips - draws current buffer and starts a new one.
  if ctx.quadCount == 0:
    return

  ctx.upload()

  glUseProgram(ctx.activeShader.programId)
  glBindVertexArray(ctx.vertexArrayId)

  if ctx.activeShader.hasUniform("windowFrame"):
    ctx.activeShader.setUniform("windowFrame", ctx.frameSize.x, ctx.frameSize.y)
  ctx.activeShader.setUniform("proj", ctx.proj)

  if ctx.activeShader.hasUniform("aaFactor"):
    ctx.activeShader.setUniform("aaFactor", ctx.aaFactor)

  if ctx.activeShader.hasUniform("maskTexEnabled"):
    ctx.activeShader.setUniform("maskTexEnabled", maskTextureRead != 0)

  if ctx.activeShader.hasUniform("atlasTex"):
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, ctx.atlasTexture.textureId)
    ctx.activeShader.setUniform("atlasTex", 0)

  if ctx.activeShader.hasUniform("maskTex"):
    if maskTextureRead != 0:
      glActiveTexture(GL_TEXTURE1)
      glBindTexture(GL_TEXTURE_2D, ctx.maskTextures[maskTextureRead].textureId)
      ctx.activeShader.setUniform("maskTex", 1)

  ctx.activeShader.bindUniforms()

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ctx.indices.buffer.bufferId)
  glDrawElements(
    GL_TRIANGLES, ctx.indices.buffer.count.GLint,
    ctx.indices.buffer.componentType, nil
  )

  ctx.quadCount = 0

proc checkBatch(ctx: Context) =
  if ctx.quadCount == ctx.maxQuads:
    # ctx is full dump the images in the ctx now and start a new batch
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

  # atlas fragment mode
  when defined(emscripten):
    let modeVal = 0.0'f32
  else:
    let modeVal = 0'u16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal

  inc ctx.quadCount

type SdfMode* {.pure.} = enum
  ## Subset of `sdfy/sdfytypes.SDFMode` with stable numeric values.
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

  when defined(emscripten):
    let modeVal = mode.int.float32
  else:
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
  ## Adds an image rect with a path to an ctx
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

  when defined(emscripten):
    let modeVal = 0.0'f32
  else:
    let modeVal = 0'u16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal

  inc ctx.quadCount

proc drawUvRect(ctx: Context, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc getImageRect(ctx: Context, imageId: Hash): Rect =
  return ctx.entries[imageId]

proc drawImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  ## Draws image the UI way - pos at top-left.
  let
    rect = ctx.getImageRect(imageId)
    wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, color)

proc drawImage*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ## Draws image the UI way - pos at top-left.
  let rect = ctx.getImageRect(imageId)
  ctx.drawUvRect(pos, pos + size, rect.xy, rect.xy + rect.wh, color)

proc drawImageAdj*(
    ctx: Context,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ## Draws image the UI way - pos at top-left.
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
  ## Draws image the game way - pos at center.
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
  ## Draws image the game way - pos at center.
  let rect = ctx.getImageRect(imageId)
  ctx.drawUvRect(pos - size / 2, pos + size / 2, rect.xy, rect.xy + rect.wh, color)

proc drawRect*(ctx: Context, rect: Rect, color: Color) =
  const imgKey = hash("rect")
  if imgKey notin ctx.entries:
    var image = newImage(4, 4)
    image.fill(rgba(255, 255, 255, 255))
    ctx.putImage(imgKey, image)

  let
    uvRect = ctx.entries[imgKey]
    wh = rect.wh * float32(ctx.atlasSize)
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

  ctx.activeShader = (if ctx.maskBegun: ctx.maskShader else: ctx.mainShader)
  ctx.checkBatch()

  let
    quadHalfExtents = rect.wh * 0.5'f32
    resolvedShapeSize =
      (if shapeSize.x > 0.0'f32 and shapeSize.y >
          0.0'f32: shapeSize else: rect.wh)
    shapeHalfExtents = resolvedShapeSize * 0.5'f32
    params =
      vec4(quadHalfExtents.x, quadHalfExtents.y, shapeHalfExtents.x,
          shapeHalfExtents.y)
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
    # (top-right, bottom-right, top-left, bottom-left)
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

  when defined(emscripten):
    let modeVal = mode.int.float32
  else:
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
  let
    uvRect = ctx.entries[hash]
    wh = vec2(w.float32, h.float32) * ctx.atlasSize.float32
  ctx.drawUvRect(
    pos, pos + vec2(w.float32, h.float32), uvRect.xy, uvRect.xy + uvRect.wh, color
  )

proc linePolygon*(ctx: Context, poly: seq[Vec2], weight: float32,
    color: Color) =
  for i in 0 ..< poly.len:
    ctx.line(poly[i], poly[(i + 1) mod poly.len], weight, color)

proc clearMask*(ctx: Context) =
  ## Sets mask off (actually fills the mask with white).
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."

  ctx.flush()

  ctx.setUpMaskFramebuffer()

  glClearColor(1, 1, 1, 1)
  glClear(GL_COLOR_BUFFER_BIT)

  glBindFramebuffer(GL_FRAMEBUFFER, 0)

proc beginMask*(ctx: Context) =
  ## Starts drawing into a mask.
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."
  assert ctx.maskBegun == false, "ctx.beginMask has already been called."
  ctx.maskBegun = true

  ctx.flush(ctx.maskTextureWrite)

  inc ctx.maskTextureWrite
  if ctx.maskTextureWrite >= ctx.maskTextures.len:
    ctx.addMaskTexture(ctx.frameSize)

  ctx.setUpMaskFramebuffer()
  glViewport(0, 0, ctx.frameSize.x.GLint, ctx.frameSize.y.GLint)

  glClearColor(0, 0, 0, 0)
  glClear(GL_COLOR_BUFFER_BIT)

  ctx.activeShader = ctx.maskShader

proc endMask*(ctx: Context) =
  ## Stops drawing into the mask.
  assert ctx.maskBegun == true, "ctx.maskBegun has not been called."
  ctx.maskBegun = false

  ctx.flush(ctx.maskTextureWrite - 1)

  glBindFramebuffer(GL_FRAMEBUFFER, 0)

  ctx.activeShader = ctx.mainShader

proc popMask*(ctx: Context) =
  ctx.flush()

  dec ctx.maskTextureWrite

proc beginFrame*(ctx: Context, frameSize: Vec2, proj: Mat4) =
  ## Starts a new frame.
  assert ctx.frameBegun == false, "ctx.beginFrame has already been called."
  ctx.frameBegun = true

  ctx.proj = proj

  if ctx.maskTextures[0].width != frameSize.x.int32 or
      ctx.maskTextures[0].height != frameSize.y.int32:
    # Resize all of the masks.
    ctx.frameSize = frameSize
    for i in 0 ..< ctx.maskTextures.len:
      ctx.maskTextures[i].width = frameSize.x.int32
      ctx.maskTextures[i].height = frameSize.y.int32
      if i > 0:
        # Never resize the 0th mask because its just white.
        bindTextureData(ctx.maskTextures[i].addr, nil)

  glViewport(0, 0, ctx.frameSize.x.GLint, ctx.frameSize.y.GLint)

  ctx.clearMask()

proc beginFrame*(ctx: Context, frameSize: Vec2) =
  beginFrame(
    ctx, frameSize, ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0)
  )

proc endFrame*(ctx: Context) =
  ## Ends a frame.
  assert ctx.frameBegun == true, "ctx.beginFrame was not called first."
  assert ctx.maskTextureWrite == 0, "Not all masks have been popped."
  ctx.frameBegun = false

  ctx.flush()

proc translate*(ctx: Context, v: Vec2) =
  ## Translate the internal transform.
  ctx.mat = ctx.mat * translate(vec3(v))

proc rotate*(ctx: Context, angle: float32) =
  ## Rotates the internal transform.
  ctx.mat = ctx.mat * rotateZ(angle)

proc scale*(ctx: Context, s: float32) =
  ## Scales the internal transform.
  ctx.mat = ctx.mat * scale(vec3(s))

proc scale*(ctx: Context, s: Vec2) =
  ## Scales the internal transform.
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))

proc saveTransform*(ctx: Context) =
  ## Pushes a transform onto the stack.
  ctx.mats.add ctx.mat

proc restoreTransform*(ctx: Context) =
  ## Pops a transform off the stack.
  ctx.mat = ctx.mats.pop()

proc clearTransform*(ctx: Context) =
  ## Clears transform and transform stack.
  ctx.mat = mat4()
  ctx.mats.setLen(0)

proc fromScreen*(ctx: Context, windowFrame: Vec2, v: Vec2): Vec2 =
  ## Takes a point from screen and translates it to point inside the current transform.
  (ctx.mat.inverse() * vec3(v.x, windowFrame.y - v.y, 0)).xy

proc toScreen*(ctx: Context, windowFrame: Vec2, v: Vec2): Vec2 =
  ## Takes a point from current transform and translates it to screen.
  result = (ctx.mat * vec3(v.x, v.y, 1)).xy
  result.y = -result.y + windowFrame.y
