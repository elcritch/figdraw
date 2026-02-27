import
  buffers, chroma, pixie, hashes, opengl, os, shaders, strformat, strutils, tables,
  textures, times

## Copied from Fidget backend, copyright from @treeform applies

import pixie/simd

import pkg/chronicles

import ../commons
import ../figbackend as figbackend
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

type OpenGlContext* = ref object of figbackend.BackendContext
  mainShader, maskShader, blurShader, activeShader: Shader
  atlasTexture: Texture
  backdropTexture: Texture
  backdropBlurTempTexture: Texture
  maskTextureWrite: int ## Index into max textures for writing.
  maskTextures: seq[Texture] ## Masks array for pushing and popping.
  atlasSize: int ## Size x size dimensions of the atlas
  atlasMargin: int ## Default margin between images
  quadCount: int ## Number of quads drawn so far
  maxQuads: int ## Max quads to draw before issuing an OpenGL call
  mat*: Mat4 ## Current matrix
  mats: seq[Mat4] ## Matrix stack
  entries*: Table[Hash, Rect] ## Mapping of image name to atlas UV position
  heights: seq[uint16] ## Height map of the free space in the atlas
  proj*: Mat4
  frameSize: Vec2 ## Dimensions of the window frame
  vertexArrayId, blurVertexArrayId, maskFramebufferId, blurFramebufferId: GLuint
  frameBegun, maskBegun: bool
  pixelate*: bool ## Makes texture look pixelated, like a pixel game.
  pixelScale*: float32 ## Multiple scaling factor.
  textLcdFilteringEnabled: bool
  textSubpixelPositioningEnabled: bool
  textSubpixelGlyphVariantsEnabled: bool
  textSubpixelShift: float32

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
  subpixelShifts: tuple[buffer: Buffer, data: seq[float32]] ## Scalar shift in px

  # SDF shader uniforms (global)
  aaFactor: float32

  # Fullscreen blur pass buffers.
  blurPositions: Buffer
  blurUvs: Buffer

proc flush(ctx: OpenGlContext, maskTextureRead: int = ctx.maskTextureWrite)

proc toKey*(h: Hash): Hash =
  h

method hasImage*(ctx: OpenGlContext, key: Hash): bool =
  key in ctx.entries

proc tryGetImageRect(ctx: OpenGlContext, imageId: Hash, rect: var Rect): bool

proc upload(ctx: OpenGlContext) =
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
  ctx.subpixelShifts.buffer.count = ctx.quadCount * 4
  bindBufferData(ctx.sdfParams.buffer.addr, ctx.sdfParams.data[0].addr)
  bindBufferData(ctx.sdfRadii.buffer.addr, ctx.sdfRadii.data[0].addr)
  bindBufferData(ctx.sdfModeAttr.buffer.addr, ctx.sdfModeAttr.data[0].addr)
  bindBufferData(ctx.sdfFactors.buffer.addr, ctx.sdfFactors.data[0].addr)
  bindBufferData(ctx.subpixelShifts.buffer.addr, ctx.subpixelShifts.data[0].addr)

proc setUpMaskFramebuffer(ctx: OpenGlContext) =
  glBindFramebuffer(GL_FRAMEBUFFER, ctx.maskFramebufferId)
  glFramebufferTexture2D(
    GL_FRAMEBUFFER,
    GL_COLOR_ATTACHMENT0,
    GL_TEXTURE_2D,
    ctx.maskTextures[ctx.maskTextureWrite].textureId,
    0,
  )

proc createAtlasTexture(ctx: OpenGlContext, size: int): Texture =
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

proc addMaskTexture(ctx: OpenGlContext, frameSize = vec2(1, 1)) =
  # Must be >0 for framebuffer creation below
  # Set to real value in beginFrame
  var maskTexture = Texture()
  maskTexture.width = frameSize.x.int32
  maskTexture.height = frameSize.y.int32
  maskTexture.componentType = GL_UNSIGNED_BYTE
  when defined(emscripten):
    maskTexture.format = GL_RGBA
    maskTexture.internalFormat = GL_RGBA8
  else:
    # Single-channel masks are enough for clip sampling in shaders (`.r`).
    # Some Wayland/EGL drivers reject RGBA data format with GL_R8 internal format.
    maskTexture.format = GL_RED
    maskTexture.internalFormat = GL_R8
  maskTexture.minFilter = minLinear
  if ctx.pixelate:
    maskTexture.magFilter = magNearest
  else:
    maskTexture.magFilter = magLinear
  when defined(emscripten):
    bindTextureData(maskTexture.addr, nil)
  else:
    try:
      bindTextureData(maskTexture.addr, nil)
    except GLerror:
      # Compatibility fallback for contexts that do not accept GL_R8/GL_RED.
      maskTexture.format = GL_RGBA
      maskTexture.internalFormat = GL_RGBA8
      bindTextureData(maskTexture.addr, nil)
  ctx.maskTextures.add(maskTexture)

proc createBackdropTexture(ctx: OpenGlContext, width, height: int): Texture =
  result.width = width.int32
  result.height = height.int32
  result.componentType = GL_UNSIGNED_BYTE
  result.format = GL_RGBA
  result.internalFormat = GL_RGBA8
  result.minFilter = minLinear
  if ctx.pixelate:
    result.magFilter = magNearest
  else:
    result.magFilter = magLinear
  result.wrapS = wClampToEdge
  result.wrapT = wClampToEdge
  bindTextureData(result.addr, nil)

proc ensureBackdropTexture(ctx: OpenGlContext, frameSize: Vec2) =
  let
    w = max(1, frameSize.x.int)
    h = max(1, frameSize.y.int)
  if ctx.backdropTexture.textureId != 0 and ctx.backdropTexture.width.int == w and
      ctx.backdropTexture.height.int == h:
    return
  ctx.backdropTexture = ctx.createBackdropTexture(w, h)

proc ensureBackdropBlurTempTexture(ctx: OpenGlContext, frameSize: Vec2) =
  let
    w = max(1, frameSize.x.int)
    h = max(1, frameSize.y.int)
  if ctx.backdropBlurTempTexture.textureId != 0 and
      ctx.backdropBlurTempTexture.width.int == w and
      ctx.backdropBlurTempTexture.height.int == h:
    return
  ctx.backdropBlurTempTexture = ctx.createBackdropTexture(w, h)

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0,
): OpenGlContext =
  ## Creates a new context.
  info "Starting OpenGL Context",
    atlasSize = atlasSize,
    atlasMargin = atlasMargin,
    maxQuads = maxQuads,
    quadLimit = quadLimit,
    pixelate = pixelate,
    pixelScale = pixelScale
  if maxQuads > quadLimit:
    raise newException(ValueError, &"Quads cannot exceed {quadLimit}")

  result = OpenGlContext()
  result.atlasSize = atlasSize
  result.atlasMargin = atlasMargin
  result.maxQuads = maxQuads
  result.mat = mat4()
  result.mats = newSeq[Mat4]()
  result.pixelate = pixelate
  result.pixelScale = pixelScale
  result.aaFactor = 1.2'f32
  result.textLcdFilteringEnabled = false
  result.textSubpixelPositioningEnabled = false
  result.textSubpixelGlyphVariantsEnabled = false
  result.textSubpixelShift = 0.0'f32

  result.heights = newSeq[uint16](atlasSize)
  result.atlasTexture = result.createAtlasTexture(atlasSize)

  result.addMaskTexture()

  when defined(emscripten) or defined(useOpenGlEs):
    result.maskShader =
      newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/mask.frag")
    result.mainShader =
      newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/atlas.frag")
    result.blurShader =
      newShaderStatic("glsl/emscripten/blur.vert", "glsl/emscripten/blur.frag")
  else:
    try:
      result.maskShader = newShaderStatic("glsl/atlas.vert", "glsl/mask.frag")
      result.mainShader = newShaderStatic("glsl/atlas.vert", "glsl/atlas.frag")
      result.blurShader = newShaderStatic("glsl/blur.vert", "glsl/blur.frag")
    except ShaderCompilationError:
      info "OpenGL 3.30 failed, trying GLSL ES fallback"
      result.maskShader =
        newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/mask.frag")
      result.mainShader =
        newShaderStatic("glsl/emscripten/atlas.vert", "glsl/emscripten/atlas.frag")
      result.blurShader =
        newShaderStatic("glsl/emscripten/blur.vert", "glsl/emscripten/blur.frag")

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
    newSeq[SdfModeData](result.sdfModeAttr.buffer.kind.componentCount() * maxQuads * 4)

  result.sdfFactors.buffer.componentType = cGL_FLOAT
  result.sdfFactors.buffer.kind = bkVEC2
  result.sdfFactors.buffer.target = GL_ARRAY_BUFFER
  result.sdfFactors.buffer.usage = GL_STREAM_DRAW
  result.sdfFactors.data =
    newSeq[float32](result.sdfFactors.buffer.kind.componentCount() * maxQuads * 4)

  result.subpixelShifts.buffer.componentType = cGL_FLOAT
  result.subpixelShifts.buffer.kind = bkSCALAR
  result.subpixelShifts.buffer.target = GL_ARRAY_BUFFER
  result.subpixelShifts.buffer.usage = GL_STREAM_DRAW
  result.subpixelShifts.data = newSeq[float32](maxQuads * 4)

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
  result.mainShader.bindAttrib("vertexSubpixelShift", result.subpixelShifts.buffer)

  # Mask shader.
  result.maskShader.bindAttrib("vertexPos", result.positions.buffer)
  result.maskShader.bindAttrib("vertexColor", result.colors.buffer)
  result.maskShader.bindAttrib("vertexUv", result.uvs.buffer)
  result.maskShader.bindAttrib("vertexSdfParams", result.sdfParams.buffer)
  result.maskShader.bindAttrib("vertexSdfRadii", result.sdfRadii.buffer)
  result.maskShader.bindAttrib("vertexSdfMode", result.sdfModeAttr.buffer)
  result.maskShader.bindAttrib("vertexSubpixelShift", result.subpixelShifts.buffer)

  # Fullscreen triangle buffers for blur passes.
  result.blurPositions.componentType = cGL_FLOAT
  result.blurPositions.kind = bkVEC2
  result.blurPositions.target = GL_ARRAY_BUFFER
  result.blurPositions.usage = GL_STATIC_DRAW
  result.blurPositions.count = 3

  result.blurUvs.componentType = cGL_FLOAT
  result.blurUvs.kind = bkVEC2
  result.blurUvs.target = GL_ARRAY_BUFFER
  result.blurUvs.usage = GL_STATIC_DRAW
  result.blurUvs.count = 3

  let blurPosData: array[6, float32] =
    [-1.0'f32, -1.0'f32, 3.0'f32, -1.0'f32, -1.0'f32, 3.0'f32]
  let blurUvData: array[6, float32] =
    [0.0'f32, 0.0'f32, 2.0'f32, 0.0'f32, 0.0'f32, 2.0'f32]
  bindBufferData(result.blurPositions.addr, unsafeAddr blurPosData[0])
  bindBufferData(result.blurUvs.addr, unsafeAddr blurUvData[0])

  glGenVertexArrays(1, result.blurVertexArrayId.addr)
  glBindVertexArray(result.blurVertexArrayId)
  result.blurShader.bindAttrib("vertexPos", result.blurPositions)
  result.blurShader.bindAttrib("vertexUv", result.blurUvs)
  glBindVertexArray(result.vertexArrayId)

  # Create mask framebuffer
  glGenFramebuffers(1, result.maskFramebufferId.addr)
  result.setUpMaskFramebuffer()

  let status = glCheckFramebufferStatus(GL_FRAMEBUFFER)
  if status != GL_FRAMEBUFFER_COMPLETE:
    quit(&"Something wrong with mask framebuffer: {toHex(status.int32, 4)}")

  glGenFramebuffers(1, result.blurFramebufferId.addr)

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

proc grow(ctx: OpenGlContext) =
  ctx.flush()
  ctx.atlasSize = ctx.atlasSize * 2
  info "grow atlasSize ", atlasSize = ctx.atlasSize
  ctx.heights.setLen(ctx.atlasSize)
  ctx.atlasTexture = ctx.createAtlasTexture(ctx.atlasSize)
  ctx.entries.clear()

proc findEmptyRect(ctx: OpenGlContext, width, height: int): Rect =
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
    #raise newException(Exception, "OpenGlContext Atlas is full")
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

method putImage*(ctx: OpenGlContext, path: Hash, image: Image) =
  # Reminder: This does not set mipmaps (used for text, should it?)
  let rect = ctx.findEmptyRect(image.width, image.height)
  ctx.entries[path] = rect / float(ctx.atlasSize)
  updateSubImage(ctx.atlasTexture, int(rect.x), int(rect.y), image)

method addImage*(ctx: OpenGlContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method updateImage*(ctx: OpenGlContext, path: Hash, image: Image) =
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

proc putFlippy*(ctx: OpenGlContext, path: Hash, flippy: Flippy) =
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

method putImage*(ctx: OpenGlContext, imgObj: ImgObj) =
  ## puts an ImgObj wrapper with either a flippy or image format
  case imgObj.kind
  of FlippyImg:
    ctx.putFlippy(imgObj.id.Hash, imgObj.flippy)
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)

proc flush(ctx: OpenGlContext, maskTextureRead: int = ctx.maskTextureWrite) =
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

  if ctx.activeShader.hasUniform("atlasTexelSize"):
    let texel = 1.0'f32 / max(ctx.atlasSize.float32, 1.0'f32)
    ctx.activeShader.setUniform("atlasTexelSize", texel, texel)

  if ctx.activeShader.hasUniform("subpixelPositioningEnabled"):
    ctx.activeShader.setUniform(
      "subpixelPositioningEnabled", ctx.textSubpixelPositioningEnabled
    )

  if ctx.activeShader.hasUniform("atlasTex"):
    glActiveTexture(GL_TEXTURE0)
    glBindTexture(GL_TEXTURE_2D, ctx.atlasTexture.textureId)
    ctx.activeShader.setUniform("atlasTex", 0)

  if ctx.activeShader.hasUniform("maskTex"):
    if maskTextureRead != 0:
      glActiveTexture(GL_TEXTURE1)
      glBindTexture(GL_TEXTURE_2D, ctx.maskTextures[maskTextureRead].textureId)
      ctx.activeShader.setUniform("maskTex", 1)

  if ctx.activeShader.hasUniform("backdropTex"):
    glActiveTexture(GL_TEXTURE2)
    glBindTexture(GL_TEXTURE_2D, ctx.backdropTexture.textureId)
    ctx.activeShader.setUniform("backdropTex", 2)

  ctx.activeShader.bindUniforms()

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ctx.indices.buffer.bufferId)
  glDrawElements(
    GL_TRIANGLES, ctx.indices.buffer.count.GLint, ctx.indices.buffer.componentType, nil
  )

  ctx.quadCount = 0

proc checkBatch(ctx: OpenGlContext) =
  if ctx.quadCount == ctx.maxQuads:
    # ctx is full dump the images in the ctx now and start a new batch
    if ctx.maskBegun:
      ctx.flush(ctx.maskTextureWrite - 1)
    else:
      ctx.flush()

proc setVert2(buf: var seq[float32], i: int, v: Vec2) =
  buf[i * 2 + 0] = v.x
  buf[i * 2 + 1] = v.y

proc setVert1(buf: var seq[float32], i: int, v: float32) =
  buf[i] = v

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

proc activeSubpixelShift(ctx: OpenGlContext): float32 =
  if not ctx.textSubpixelPositioningEnabled:
    return 0.0'f32
  max(0.0'f32, min(ctx.textSubpixelShift, 0.999'f32))

proc setQuadSubpixelShift(ctx: OpenGlContext, offset: int) =
  let shift = ctx.activeSubpixelShift()
  ctx.subpixelShifts.data.setVert1(offset + 0, shift)
  ctx.subpixelShifts.data.setVert1(offset + 1, shift)
  ctx.subpixelShifts.data.setVert1(offset + 2, shift)
  ctx.subpixelShifts.data.setVert1(offset + 3, shift)

func `*`*(m: Mat4, v: Vec2): Vec2 =
  (m * vec3(v.x, v.y, 0.0)).xy

proc drawQuad*(
    ctx: OpenGlContext,
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
  ctx.setQuadSubpixelShift(offset)

  inc ctx.quadCount

type SdfMode* = figbackend.SdfMode

proc drawUvRectAtlasSdf(
    ctx: OpenGlContext,
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

  when defined(emscripten):
    let modeVal = mode.int.float32
  else:
    let modeVal = mode.int.uint16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal
  ctx.setQuadSubpixelShift(offset)

  inc ctx.quadCount

method drawMsdfImage*(
    ctx: OpenGlContext,
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
    ctx: OpenGlContext,
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

proc setSdfGlobals*(ctx: OpenGlContext, aaFactor: float32) =
  if ctx.aaFactor == aaFactor:
    return
  ctx.aaFactor = aaFactor

proc drawUvRect(ctx: OpenGlContext, at, to: Vec2, uvAt, uvTo: Vec2, color: Color) =
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
  ctx.setQuadSubpixelShift(offset)

  inc ctx.quadCount

proc drawUvRect(
    ctx: OpenGlContext, at, to: Vec2, uvAt, uvTo: Vec2, colors: array[4, ColorRGBA]
) =
  ## Adds an image rect with explicit per-vertex colors.
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

  when defined(emscripten):
    let modeVal = 0.0'f32
  else:
    let modeVal = 0'u16
  ctx.sdfModeAttr.data[offset + 0] = modeVal
  ctx.sdfModeAttr.data[offset + 1] = modeVal
  ctx.sdfModeAttr.data[offset + 2] = modeVal
  ctx.sdfModeAttr.data[offset + 3] = modeVal
  ctx.setQuadSubpixelShift(offset)

  inc ctx.quadCount

proc drawUvRect(ctx: OpenGlContext, rect, uvRect: Rect, color: Color) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, color)

proc drawUvRect(ctx: OpenGlContext, rect, uvRect: Rect, colors: array[4, ColorRGBA]) =
  ctx.drawUvRect(rect.xy, rect.xy + rect.wh, uvRect.xy, uvRect.xy + uvRect.wh, colors)

proc tryGetImageRect(ctx: OpenGlContext, imageId: Hash, rect: var Rect): bool =
  if imageId notin ctx.entries:
    warn "missing image in context", imageId = imageId
    return false
  rect = ctx.entries[imageId]
  true

proc drawImage*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale: float32,
) =
  ## Draws image the UI way - pos at top-left.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, color)

method drawImage*(ctx: OpenGlContext, imageId: Hash, pos: Vec2, color: Color) =
  drawImage(ctx, imageId, pos, color, 1.0'f32)

proc drawImage*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    colors: array[4, ColorRGBA],
    scale: float32,
) =
  ## Draws image the UI way - pos at top-left with per-vertex colors.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos, pos + wh, rect.xy, rect.xy + rect.wh, colors)

method drawImage*(
    ctx: OpenGlContext, imageId: Hash, pos: Vec2, colors: array[4, ColorRGBA]
) =
  drawImage(ctx, imageId, pos, colors, 1.0'f32)

method drawImage*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ## Draws image the UI way - pos at top-left.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos, pos + size, rect.xy, rect.xy + rect.wh, color)

method drawImage*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    colors: array[4, ColorRGBA],
    size: Vec2,
) =
  ## Draws image the UI way - pos at top-left with per-vertex colors.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos, pos + size, rect.xy, rect.xy + rect.wh, colors)

method drawImageAdj*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ## Draws image the UI way - pos at top-left.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let adj = vec2(2 / ctx.atlasSize.float32)
  ctx.drawUvRect(pos, pos + size, rect.xy + adj, rect.xy + rect.wh - adj, color)

proc drawSprite*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    scale = 1.0,
) =
  ## Draws image the game way - pos at center.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  let wh = rect.wh * ctx.atlasSize.float32 * scale
  ctx.drawUvRect(pos - wh / 2, pos + wh / 2, rect.xy, rect.xy + rect.wh, color)

proc drawSprite*(
    ctx: OpenGlContext,
    imageId: Hash,
    pos: Vec2 = vec2(0, 0),
    color = color(1, 1, 1, 1),
    size: Vec2,
) =
  ## Draws image the game way - pos at center.
  var rect: Rect
  if not ctx.tryGetImageRect(imageId, rect):
    return
  ctx.drawUvRect(pos - size / 2, pos + size / 2, rect.xy, rect.xy + rect.wh, color)

method drawRect*(ctx: OpenGlContext, rect: Rect, color: Color) =
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

method drawRoundedRectSdf*(
    ctx: OpenGlContext,
    rect: Rect,
    color: Color,
    radii: array[DirectionCorners, float32],
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

method drawRoundedRectSdf*(
    ctx: OpenGlContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
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

  ctx.colors.data.setVertColor(offset + 0, colors[0])
  ctx.colors.data.setVertColor(offset + 1, colors[1])
  ctx.colors.data.setVertColor(offset + 2, colors[2])
  ctx.colors.data.setVertColor(offset + 3, colors[3])

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
  ctx.setQuadSubpixelShift(offset)

  inc ctx.quadCount

proc runBackdropSeparableBlur(ctx: OpenGlContext, blurRadius: float32) =
  if blurRadius <= 0.5'f32:
    return

  ctx.ensureBackdropBlurTempTexture(ctx.frameSize)

  let w = max(1.0'f32, ctx.frameSize.x)
  let h = max(1.0'f32, ctx.frameSize.y)
  let wasBlendEnabled = glIsEnabled(GL_BLEND) == GL_TRUE
  if wasBlendEnabled:
    glDisable(GL_BLEND)

  glUseProgram(ctx.blurShader.programId)
  glBindVertexArray(ctx.blurVertexArrayId)
  ctx.blurShader.setUniform("srcTex", 0)
  ctx.blurShader.setUniform("blurRadius", blurRadius)

  glBindFramebuffer(GL_FRAMEBUFFER, ctx.blurFramebufferId)
  glViewport(0, 0, ctx.frameSize.x.GLint, ctx.frameSize.y.GLint)

  glActiveTexture(GL_TEXTURE0)
  glBindTexture(GL_TEXTURE_2D, ctx.backdropTexture.textureId)
  glFramebufferTexture2D(
    GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D,
    ctx.backdropBlurTempTexture.textureId, 0,
  )
  ctx.blurShader.setUniform("texelStep", 1.0'f32 / w, 0.0'f32)
  ctx.blurShader.bindUniforms()
  glDrawArrays(GL_TRIANGLES, 0, 3)

  glBindTexture(GL_TEXTURE_2D, ctx.backdropBlurTempTexture.textureId)
  glFramebufferTexture2D(
    GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, ctx.backdropTexture.textureId,
    0,
  )
  ctx.blurShader.setUniform("texelStep", 0.0'f32, 1.0'f32 / h)
  ctx.blurShader.bindUniforms()
  glDrawArrays(GL_TRIANGLES, 0, 3)

  glBindFramebuffer(GL_FRAMEBUFFER, 0)
  glBindVertexArray(ctx.vertexArrayId)

  if wasBlendEnabled:
    glEnable(GL_BLEND)

method drawBackdropBlur*(
    ctx: OpenGlContext,
    rect: Rect,
    radii: array[DirectionCorners, float32],
    blurRadius: float32,
) =
  if blurRadius <= 0.0'f32 or rect.w <= 0.0'f32 or rect.h <= 0.0'f32:
    return

  if ctx.maskBegun:
    ctx.flush(ctx.maskTextureWrite - 1)
  else:
    ctx.flush()

  ctx.ensureBackdropTexture(ctx.frameSize)

  glActiveTexture(GL_TEXTURE2)
  glBindTexture(GL_TEXTURE_2D, ctx.backdropTexture.textureId)

  var canSelectReadBuffer = true
  try:
    glReadBuffer(GL_BACK)
    if glGetError() != GL_NO_ERROR:
      # Wayland/EGL may expose a single-buffer drawable where GL_BACK is invalid.
      glReadBuffer(GL_FRONT)
  except GLerror:
    # GLES/EGL paths can reject glReadBuffer; default framebuffer read buffer is used.
    canSelectReadBuffer = false

  glCopyTexSubImage2D(
    GL_TEXTURE_2D,
    0,
    0,
    0,
    0,
    0,
    max(1, ctx.frameSize.x.int).GLsizei,
    max(1, ctx.frameSize.y.int).GLsizei,
  )

  if canSelectReadBuffer:
    try:
      glReadBuffer(GL_BACK)
    except GLerror:
      discard

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

proc line*(ctx: OpenGlContext, a: Vec2, b: Vec2, weight: float32, color: Color) =
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

proc linePolygon*(ctx: OpenGlContext, poly: seq[Vec2], weight: float32, color: Color) =
  for i in 0 ..< poly.len:
    ctx.line(poly[i], poly[(i + 1) mod poly.len], weight, color)

proc clearMask*(ctx: OpenGlContext) =
  ## Sets mask off (actually fills the mask with white).
  assert ctx.frameBegun == true, "ctx.beginFrame has not been called."

  ctx.flush()

  ctx.setUpMaskFramebuffer()

  glClearColor(1, 1, 1, 1)
  glClear(GL_COLOR_BUFFER_BIT)

  glBindFramebuffer(GL_FRAMEBUFFER, 0)

method beginMask*(
    ctx: OpenGlContext, clipRect: Rect, radii: array[DirectionCorners, float32]
) =
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

  ctx.drawRoundedRectSdf(
    rect = clipRect,
    color = rgba(255, 0, 0, 255).color,
    radii = radii,
    mode = figbackend.SdfMode.sdfModeClipAA,
    factor = 4.0'f32,
    spread = 0.0'f32,
    shapeSize = vec2(0.0'f32, 0.0'f32),
  )

method endMask*(ctx: OpenGlContext) =
  ## Stops drawing into the mask.
  assert ctx.maskBegun == true, "ctx.maskBegun has not been called."
  ctx.maskBegun = false

  ctx.flush(ctx.maskTextureWrite - 1)

  glBindFramebuffer(GL_FRAMEBUFFER, 0)

  ctx.activeShader = ctx.mainShader

method popMask*(ctx: OpenGlContext) =
  ctx.flush()

  dec ctx.maskTextureWrite

proc beginFrameProj(ctx: OpenGlContext, frameSize: Vec2, proj: Mat4) =
  ## Starts a new frame.
  assert ctx.frameBegun == false, "ctx.beginFrame has already been called."
  ctx.frameBegun = true

  ctx.proj = proj
  ctx.frameSize = frameSize

  if ctx.maskTextures[0].width != frameSize.x.int32 or
      ctx.maskTextures[0].height != frameSize.y.int32:
    # Resize all of the masks.
    for i in 0 ..< ctx.maskTextures.len:
      ctx.maskTextures[i].width = frameSize.x.int32
      ctx.maskTextures[i].height = frameSize.y.int32
      if i > 0:
        # Never resize the 0th mask because its just white.
        bindTextureData(ctx.maskTextures[i].addr, nil)

  ctx.ensureBackdropTexture(frameSize)

  glViewport(0, 0, ctx.frameSize.x.GLint, ctx.frameSize.y.GLint)

  ctx.clearMask()

proc beginFrameDefaultProj(ctx: OpenGlContext, frameSize: Vec2) =
  beginFrameProj(
    ctx, frameSize, ortho[float32](0.0, frameSize.x, frameSize.y, 0, -1000.0, 1000.0)
  )

method endFrame*(ctx: OpenGlContext) =
  ## Ends a frame.
  assert ctx.frameBegun == true, "ctx.beginFrame was not called first."
  assert ctx.maskTextureWrite == 0, "Not all masks have been popped."
  ctx.frameBegun = false

  ctx.flush()

method translate*(ctx: OpenGlContext, v: Vec2) =
  ## Translate the internal transform.
  ctx.mat = ctx.mat * translate(vec3(v))

method rotate*(ctx: OpenGlContext, angle: float32) =
  ## Rotates the internal transform.
  ctx.mat = ctx.mat * rotateZ(angle)

method scale*(ctx: OpenGlContext, s: float32) =
  ## Scales the internal transform.
  ctx.mat = ctx.mat * scale(vec3(s))

method scale*(ctx: OpenGlContext, s: Vec2) =
  ## Scales the internal transform.
  ctx.mat = ctx.mat * scale(vec3(s.x, s.y, 1))

method saveTransform*(ctx: OpenGlContext) =
  ## Pushes a transform onto the stack.
  ctx.mats.add ctx.mat

method restoreTransform*(ctx: OpenGlContext) =
  ## Pops a transform off the stack.
  ctx.mat = ctx.mats.pop()

proc clearTransform*(ctx: OpenGlContext) =
  ## Clears transform and transform stack.
  ctx.mat = mat4()
  ctx.mats.setLen(0)

proc fromScreen*(ctx: OpenGlContext, windowFrame: Vec2, v: Vec2): Vec2 =
  ## Takes a point from screen and translates it to point inside the current transform.
  (ctx.mat.inverse() * vec3(v.x, windowFrame.y - v.y, 0)).xy

proc toScreen*(ctx: OpenGlContext, windowFrame: Vec2, v: Vec2): Vec2 =
  ## Takes a point from current transform and translates it to screen.
  result = (ctx.mat * vec3(v.x, v.y, 1)).xy
  result.y = -result.y + windowFrame.y

method kind*(ctx: OpenGlContext): figbackend.RendererBackendKind =
  figbackend.RendererBackendKind.rbOpenGL

method entriesPtr*(ctx: OpenGlContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method pixelScale*(ctx: OpenGlContext): float32 =
  ctx.pixelScale

method textLcdFilteringEnabled*(ctx: OpenGlContext): bool =
  ctx.textLcdFilteringEnabled

method setTextLcdFilteringEnabled*(ctx: OpenGlContext, enabled: bool) =
  ctx.textLcdFilteringEnabled = enabled

method textSubpixelPositioningEnabled*(ctx: OpenGlContext): bool =
  ctx.textSubpixelPositioningEnabled

method setTextSubpixelPositioningEnabled*(ctx: OpenGlContext, enabled: bool) =
  ctx.textSubpixelPositioningEnabled = enabled

method textSubpixelGlyphVariantsEnabled*(ctx: OpenGlContext): bool =
  ctx.textSubpixelGlyphVariantsEnabled

method setTextSubpixelGlyphVariantsEnabled*(ctx: OpenGlContext, enabled: bool) =
  ctx.textSubpixelGlyphVariantsEnabled = enabled

method setTextSubpixelShift*(ctx: OpenGlContext, shift: float32) =
  ctx.textSubpixelShift = shift

method beginFrame*(
    ctx: OpenGlContext,
    frameSize: Vec2,
    clearMain = false,
    clearMainColor: Color = whiteColor,
) =
  if clearMain:
    glClearColor(
      clearMainColor.r.GLfloat, clearMainColor.g.GLfloat, clearMainColor.b.GLfloat,
      clearMainColor.a.GLfloat,
    )
    glClear(GL_COLOR_BUFFER_BIT)
  beginFrameDefaultProj(ctx, frameSize)

method readPixels*(ctx: OpenGlContext, frame: Rect, readFront: bool): Image =
  var viewport: array[4, GLint]
  glGetIntegerv(GL_VIEWPORT, viewport[0].addr)

  let
    viewportWidth = viewport[2].int
    viewportHeight = viewport[3].int

  var x = frame.x.int
  var y = frame.y.int
  var w = frame.w.int
  var h = frame.h.int

  if w <= 0 or h <= 0:
    x = 0
    y = 0
    w = viewportWidth
    h = viewportHeight

  if w <= 0 or h <= 0:
    return newImage(0, 0)

  let wantBack = not readFront
  var canSelectReadBuffer = true
  try:
    glReadBuffer(if wantBack: GL_BACK else: GL_FRONT)
    if wantBack and glGetError() != GL_NO_ERROR:
      # Wayland/EGL may expose a single-buffer drawable where GL_BACK is invalid.
      glReadBuffer(GL_FRONT)
  except GLerror:
    # GLES/EGL paths can reject glReadBuffer; read from default color buffer.
    canSelectReadBuffer = false
  result = newImage(w, h)
  glReadPixels(
    x.GLint, y.GLint, w.GLint, h.GLint, GL_RGBA, GL_UNSIGNED_BYTE, result.data[0].addr
  )
  result.flipVertical()
  if canSelectReadBuffer:
    try:
      glReadBuffer(GL_BACK)
    except GLerror:
      discard
