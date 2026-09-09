import buffers, pixie, opengl
import std/strutils

type
  MinFilter* = enum
    minDefault
    minNearest = GL_NEAREST
    minLinear = GL_LINEAR
    minNearestMipmapNearest = GL_NEAREST_MIPMAP_NEAREST
    minLinearMipmapNearest = GL_LINEAR_MIPMAP_NEAREST
    minNearestMipmapLinear = GL_NEAREST_MIPMAP_LINEAR
    minLinearMipmapLinear = GL_LINEAR_MIPMAP_LINEAR

  MagFilter* = enum
    magDefault
    magNearest = GL_NEAREST
    magLinear = GL_LINEAR

  Wrap* = enum
    wDefault
    wRepeat = GL_REPEAT
    wClampToEdge = GL_CLAMP_TO_EDGE
    wMirroredRepeat = GL_MIRRORED_REPEAT

  Texture* = object
    width*, height*: int32
    componentType*, format*, internalFormat*: GLenum
    minFilter*: MinFilter
    magFilter*: MagFilter
    wrapS*, wrapT*: Wrap
    genMipmap*: bool
    textureId*: GLuint

proc bindTextureBufferData*(texture: ptr Texture, buffer: ptr Buffer, data: pointer) =
  bindBufferData(buffer, data)

  if texture.textureId == 0:
    glGenTextures(1, texture.textureId.addr)

  glBindTexture(GL_TEXTURE_BUFFER, texture.textureId)
  glTexBuffer(GL_TEXTURE_BUFFER, texture.internalFormat, buffer.bufferId)

proc hasModernTransferState*(): bool =
  ## GLES 2 / WebGL 1 only support alignment and a single framebuffer binding.
  let raw = cast[cstring](glGetString(GL_VERSION))
  if raw.isNil:
    return false
  let version = $raw
  not (
    version.startsWith("OpenGL ES 2") or version.startsWith("OpenGL ES 1") or
    version.startsWith("WebGL 1")
  )

template withClientPixels*(unpack: static bool, body: untyped) =
  ## Client-memory transfers must not inherit another renderer's PBO or strides.
  block:
    const
      alignment = when unpack: GL_UNPACK_ALIGNMENT else: GL_PACK_ALIGNMENT
      rowLength = when unpack: GL_UNPACK_ROW_LENGTH else: GL_PACK_ROW_LENGTH
      skipRows = when unpack: GL_UNPACK_SKIP_ROWS else: GL_PACK_SKIP_ROWS
      skipPixels = when unpack: GL_UNPACK_SKIP_PIXELS else: GL_PACK_SKIP_PIXELS
      bufferTarget = when unpack: GL_PIXEL_UNPACK_BUFFER else: GL_PIXEL_PACK_BUFFER
      bufferBinding =
        when unpack: GL_PIXEL_UNPACK_BUFFER_BINDING else: GL_PIXEL_PACK_BUFFER_BINDING
    var savedAlignment, savedRowLength, savedSkipRows, savedSkipPixels, savedBuffer:
      GLint
    let modern = hasModernTransferState()
    glGetIntegerv(alignment, savedAlignment.addr)
    glPixelStorei(alignment, 1)
    if modern:
      glGetIntegerv(rowLength, savedRowLength.addr)
      glGetIntegerv(skipRows, savedSkipRows.addr)
      glGetIntegerv(skipPixels, savedSkipPixels.addr)
      glGetIntegerv(bufferBinding, savedBuffer.addr)
      glBindBuffer(bufferTarget, 0)
      glPixelStorei(rowLength, 0)
      glPixelStorei(skipRows, 0)
      glPixelStorei(skipPixels, 0)
    defer:
      glPixelStorei(alignment, savedAlignment)
      if modern:
        glPixelStorei(rowLength, savedRowLength)
        glPixelStorei(skipRows, savedSkipRows)
        glPixelStorei(skipPixels, savedSkipPixels)
        glBindBuffer(bufferTarget, savedBuffer.GLuint)
    body

proc bindTextureData*(texture: ptr Texture, data: pointer) =
  if texture.textureId == 0:
    glGenTextures(1, texture.textureId.addr)

  glBindTexture(GL_TEXTURE_2D, texture.textureId)
  withClientPixels(true):
    glTexImage2D(
      target = GL_TEXTURE_2D,
      level = 0,
      internalFormat = texture.internalFormat.GLint,
      width = texture.width,
      height = texture.height,
      border = 0,
      format = texture.format,
      `type` = texture.componentType,
      pixels = data,
    )

  if texture.magFilter != magDefault:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, texture.magFilter.GLint)
  if texture.minFilter != minDefault:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, texture.minFilter.GLint)
  if texture.wrapS != wDefault:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, texture.wrapS.GLint)
  if texture.wrapT != wDefault:
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, texture.wrapT.GLint)

  if texture.genMipmap:
    glGenerateMipmap(GL_TEXTURE_2D)

func getFormat(image: Image): GLenum =
  result = GL_RGBA

proc initTexture*(image: Image): Texture =
  if image.isNil or image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "Cannot upload an empty image")
  result.width = image.width.GLint
  result.height = image.height.GLint
  result.componentType = GL_UNSIGNED_BYTE
  result.format = image.getFormat()
  result.internalFormat = GL_RGBA8
  result.genMipmap = true
  result.minFilter = minLinearMipmapLinear
  result.magFilter = magLinear
  var data = newSeq[ColorRGBA](image.width * image.height)
  for i in 0 ..< data.len:
    data[i] = image.data[i]
  bindTextureData(result.addr, data[0].addr)

proc updateSubImage*(texture: Texture, x, y: int, image: Image, level: int) =
  ## Update a small part of a texture image.
  if image.isNil or image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "Cannot upload an empty image")
  if level < 0 or level >= 31 or x < 0 or y < 0 or
      image.width > max(1, texture.width.int shr level) - x or
      image.height > max(1, texture.height.int shr level) - y:
    raise newException(ValueError, "Texture upload exceeds the mip level bounds")
  var data = newSeq[ColorRGBA](image.width * image.height)
  for i in 0 ..< data.len:
    data[i] = image.data[i]
  glBindTexture(GL_TEXTURE_2D, texture.textureId)
  withClientPixels(true):
    glTexSubImage2D(
      GL_TEXTURE_2D,
      level = level.GLint,
      xoffset = x.GLint,
      yoffset = y.GLint,
      width = image.width.GLint,
      height = image.height.GLint,
      format = image.getFormat(),
      `type` = GL_UNSIGNED_BYTE,
      pixels = data[0].addr,
    )

proc updateSubImage*(texture: Texture, x, y: int, image: Image) =
  ## Update a small part of texture with a new image.
  var
    x = x
    y = y
    image = image
    level = 0

  while true:
    texture.updateSubImage(x, y, image, level)
    if not texture.genMipmap or (image.width == 1 and image.height == 1):
      break
    image = image.resize(max(1, image.width div 2), max(1, image.height div 2))
    x = x div 2
    y = y div 2
    inc level
