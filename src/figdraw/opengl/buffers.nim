import glapi

type
  BufferKind* = enum
    bkSCALAR
    bkVEC2
    bkVEC3
    bkVEC4
    bkMAT2
    bkMAT3
    bkMAT4

  Buffer* = object
    count*: int
    target*, componentType*: GLenum
    kind*: BufferKind
    normalized*: bool
    usage*: GLenum
    bufferId*: GlBufferId
    byteCapacity*: int

func size*(componentType: GLenum): Positive =
  case componentType
  of cGL_BYTE, cGL_UNSIGNED_BYTE:
    1
  of cGL_SHORT, cGL_UNSIGNED_SHORT:
    2
  of cGL_INT, GL_UNSIGNED_INT, cGL_FLOAT:
    4
  else:
    raise newException(Exception, "Unexpected componentType")

func componentCount*(bufferKind: BufferKind): Positive =
  case bufferKind
  of bkSCALAR: 1
  of bkVEC2: 2
  of bkVEC3: 3
  of bkVEC4, bkMAT2: 4
  of bkMAT3: 9
  of bkMAT4: 16

when defined(js):
  proc bindBufferData*[T](buffer: ptr Buffer, data: openArray[T]) =
    if buffer.bufferId.isNil:
      buffer.bufferId = glCreateBuffer()

    let byteLength =
      buffer.count * buffer.kind.componentCount() * buffer.componentType.size()
    let usage = if buffer.usage == 0.GLenum: GL_STATIC_DRAW else: buffer.usage

    glBindBuffer(buffer.target, buffer.bufferId)
    if byteLength <= 0:
      return

    when T is float32:
      glBufferData(buffer.target, newFloat32Array(data), usage)
    elif T is uint16:
      glBufferData(buffer.target, newUint16Array(data), usage)
    elif T is uint8:
      glBufferData(buffer.target, newUint8Array(data), usage)
    else:
      {.fatal: "Unsupported buffer data type for WebGL.".}

    buffer.byteCapacity = byteLength
else:
  proc bindBufferData*(buffer: ptr Buffer, data: pointer) =
    if buffer.bufferId == 0:
      glGenBuffers(1, buffer.bufferId.addr)

    let byteLength =
      buffer.count * buffer.kind.componentCount() * buffer.componentType.size()

    glBindBuffer(buffer.target, buffer.bufferId)
    if buffer.byteCapacity < byteLength:
      let usage = if buffer.usage == 0.GLenum: GL_STATIC_DRAW else: buffer.usage
      glBufferData(buffer.target, byteLength, nil, usage)
      buffer.byteCapacity = byteLength

    if data != nil and byteLength > 0:
      glBufferSubData(buffer.target, 0, byteLength, data)
