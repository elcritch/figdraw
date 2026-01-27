when defined(js):
  import std/jsffi
  import ../webgl/api as webgl

  export webgl.GLenum, webgl.GLboolean, webgl.GLbitfield, webgl.GLbyte,
    webgl.GLshort, webgl.GLint, webgl.GLsizei, webgl.GLintptr, webgl.GLsizeiptr,
    webgl.GLubyte, webgl.GLushort, webgl.GLuint, webgl.GLfloat, webgl.GLclampf

  type
    GlBufferId* = webgl.WebGLBuffer
    GlTextureId* = webgl.WebGLTexture
    GlProgramId* = webgl.WebGLProgram
    GlShaderId* = webgl.WebGLShader
    GlVertexArrayId* = webgl.WebGLVertexArrayObject
    GlFramebufferId* = webgl.WebGLFramebuffer
    GlUniformLocation* = webgl.WebGLUniformLocation
    WebGL2RenderingContext* = webgl.WebGL2RenderingContext

  const
    GL_FALSE* = false
    GL_TRUE* = true

    GL_NO_ERROR* = 0.GLenum

    GL_BYTE* = 0x1400.GLenum
    GL_UNSIGNED_BYTE* = 0x1401.GLenum
    GL_SHORT* = 0x1402.GLenum
    GL_UNSIGNED_SHORT* = 0x1403.GLenum
    GL_INT* = 0x1404.GLenum
    GL_UNSIGNED_INT* = 0x1405.GLenum
    GL_FLOAT* = 0x1406.GLenum

    GL_TEXTURE_2D* = 0x0DE1.GLenum
    GL_TEXTURE_BUFFER* = 0x8C2A.GLenum
    GL_TEXTURE0* = 0x84C0.GLenum
    GL_TEXTURE1* = 0x84C1.GLenum
    GL_TEXTURE_MAG_FILTER* = 0x2800.GLenum
    GL_TEXTURE_MIN_FILTER* = 0x2801.GLenum
    GL_TEXTURE_WRAP_S* = 0x2802.GLenum
    GL_TEXTURE_WRAP_T* = 0x2803.GLenum

    GL_NEAREST* = 0x2600.GLenum
    GL_LINEAR* = 0x2601.GLenum
    GL_NEAREST_MIPMAP_NEAREST* = 0x2700.GLenum
    GL_LINEAR_MIPMAP_NEAREST* = 0x2701.GLenum
    GL_NEAREST_MIPMAP_LINEAR* = 0x2702.GLenum
    GL_LINEAR_MIPMAP_LINEAR* = 0x2703.GLenum

    GL_REPEAT* = 0x2901.GLenum
    GL_CLAMP_TO_EDGE* = 0x812F.GLenum
    GL_MIRRORED_REPEAT* = 0x8370.GLenum

    GL_RGBA* = 0x1908.GLenum
    GL_RGBA8* = 0x8058.GLenum
    GL_R8* = 0x8229.GLenum

    GL_FRAMEBUFFER* = 0x8D40.GLenum
    GL_COLOR_ATTACHMENT0* = 0x8CE0.GLenum
    GL_FRAMEBUFFER_COMPLETE* = 0x8CD5.GLenum

    GL_ARRAY_BUFFER* = 0x8892.GLenum
    GL_ELEMENT_ARRAY_BUFFER* = 0x8893.GLenum
    GL_UNIFORM_BUFFER* = 0x8A11.GLenum

    GL_STREAM_DRAW* = 0x88E0.GLenum
    GL_STATIC_DRAW* = 0x88E4.GLenum

    GL_TRIANGLES* = 0x0004.GLenum

    GL_COLOR_BUFFER_BIT* = 0x4000.GLenum
    GL_DEPTH_BUFFER_BIT* = 0x0100.GLenum

    GL_BLEND* = 0x0BE2.GLenum
    GL_SRC_ALPHA* = 0x0302.GLenum
    GL_ONE_MINUS_SRC_ALPHA* = 0x0303.GLenum
    GL_ONE* = 1.GLenum

    GL_DEPTH_TEST* = 0x0B71.GLenum
    GL_LEQUAL* = 0x0203.GLenum

    GL_INFO_LOG_LENGTH* = 0x8B84.GLenum
    GL_COMPILE_STATUS* = 0x8B81.GLenum
    GL_LINK_STATUS* = 0x8B82.GLenum
    GL_ACTIVE_ATTRIBUTES* = 0x8B89.GLenum
    GL_ACTIVE_UNIFORMS* = 0x8B86.GLenum

    GL_VERTEX_SHADER* = 0x8B31.GLenum
    GL_FRAGMENT_SHADER* = 0x8B30.GLenum
    GL_COMPUTE_SHADER* = 0x91B9.GLenum

    GL_CONTEXT_FLAGS* = 0x821E.GLenum
    GL_CONTEXT_FLAG_DEBUG_BIT* = 0x00000002.GLenum
    GL_DEBUG_SEVERITY_NOTIFICATION* = 0x826B.GLenum
    GL_DEBUG_OUTPUT_SYNCHRONOUS* = 0x8242.GLenum
    GL_DEBUG_OUTPUT* = 0x92E0.GLenum

    cGL_FLOAT* = GL_FLOAT
    cGL_INT* = GL_INT
    cGL_BYTE* = GL_BYTE
    cGL_SHORT* = GL_SHORT
    cGL_UNSIGNED_BYTE* = GL_UNSIGNED_BYTE
    cGL_UNSIGNED_SHORT* = GL_UNSIGNED_SHORT

  var glCtx* {.importc: "glCtx", nodecl.}: WebGL2RenderingContext

  proc setWebGLContext*(ctx: WebGL2RenderingContext) =
    glCtx = ctx

  proc newFloat32Array*(data: openArray[float32]): webgl.Float32Array
    {.importjs: "new Float32Array(#)".}
  proc newUint16Array*(data: openArray[uint16]): webgl.Uint16Array
    {.importjs: "new Uint16Array(#)".}
  proc newUint8Array*(data: openArray[uint8]): webgl.Uint8Array
    {.importjs: "new Uint8Array(#)".}

  proc glCreateBuffer*(): GlBufferId {.importjs: "glCtx.createBuffer()".}
  proc glCreateTexture*(): GlTextureId {.importjs: "glCtx.createTexture()".}
  proc glCreateVertexArray*(): GlVertexArrayId
    {.importjs: "glCtx.createVertexArray()".}
  proc glCreateFramebuffer*(): GlFramebufferId
    {.importjs: "glCtx.createFramebuffer()".}

  proc glCreateShader*(kind: GLenum): GlShaderId
    {.importjs: "glCtx.createShader(#)".}
  proc glShaderSource*(shader: GlShaderId; source: cstring)
    {.importjs: "glCtx.shaderSource(#, #)".}
  proc glCompileShader*(shader: GlShaderId)
    {.importjs: "glCtx.compileShader(#)".}
  proc glGetShaderInfoLog*(shader: GlShaderId): cstring
    {.importjs: "glCtx.getShaderInfoLog(#)".}
  proc glGetShaderParameter*(shader: GlShaderId; pname: GLenum): bool
    {.importjs: "glCtx.getShaderParameter(#, #)".}

  proc glCreateProgram*(): GlProgramId {.importjs: "glCtx.createProgram()".}
  proc glAttachShader*(program: GlProgramId; shader: GlShaderId)
    {.importjs: "glCtx.attachShader(#, #)".}
  proc glLinkProgram*(program: GlProgramId)
    {.importjs: "glCtx.linkProgram(#)".}
  proc glGetProgramInfoLog*(program: GlProgramId): cstring
    {.importjs: "glCtx.getProgramInfoLog(#)".}
  proc glGetProgramParameter*(program: GlProgramId; pname: GLenum): int
    {.importjs: "glCtx.getProgramParameter(#, #)".}

  proc glUseProgram*(program: GlProgramId)
    {.importjs: "glCtx.useProgram(#)".}

  proc glGetAttribLocation*(program: GlProgramId; name: cstring): GLint
    {.importjs: "glCtx.getAttribLocation(#, #)".}
  proc glGetUniformLocation*(program: GlProgramId;
      name: cstring): GlUniformLocation
    {.importjs: "glCtx.getUniformLocation(#, #)".}

  proc glGetActiveAttrib*(program: GlProgramId;
      index: GLuint): webgl.WebGLActiveInfo
    {.importjs: "glCtx.getActiveAttrib(#, #)".}
  proc glGetActiveUniform*(program: GlProgramId;
      index: GLuint): webgl.WebGLActiveInfo
    {.importjs: "glCtx.getActiveUniform(#, #)".}

  proc glUniform1i*(location: GlUniformLocation; v0: GLint)
    {.importjs: "glCtx.uniform1i(#, #)".}
  proc glUniform2i*(location: GlUniformLocation; v0, v1: GLint)
    {.importjs: "glCtx.uniform2i(#, #, #)".}
  proc glUniform3i*(location: GlUniformLocation; v0, v1, v2: GLint)
    {.importjs: "glCtx.uniform3i(#, #, #, #)".}
  proc glUniform4i*(location: GlUniformLocation; v0, v1, v2, v3: GLint)
    {.importjs: "glCtx.uniform4i(#, #, #, #, #)".}

  proc glUniform1f*(location: GlUniformLocation; v0: GLfloat)
    {.importjs: "glCtx.uniform1f(#, #)".}
  proc glUniform2f*(location: GlUniformLocation; v0, v1: GLfloat)
    {.importjs: "glCtx.uniform2f(#, #, #)".}
  proc glUniform3f*(location: GlUniformLocation; v0, v1, v2: GLfloat)
    {.importjs: "glCtx.uniform3f(#, #, #, #)".}
  proc glUniform4f*(location: GlUniformLocation; v0, v1, v2, v3: GLfloat)
    {.importjs: "glCtx.uniform4f(#, #, #, #, #)".}

  proc glUniformMatrix4fvRaw*(location: GlUniformLocation; transpose: GLboolean;
      value: webgl.Float32Array) {.importjs: "glCtx.uniformMatrix4fv(#, #, #)".}

  proc glUniformMatrix4fv*(
      location: GlUniformLocation; count: GLsizei; transpose: GLboolean;
      value: openArray[float32];
  ) =
    if count <= 0:
      return
    glUniformMatrix4fvRaw(location, transpose, newFloat32Array(value))

  proc glBindBuffer*(target: GLenum; buffer: GlBufferId)
    {.importjs: "glCtx.bindBuffer(#, #)".}

  proc glBufferData*(target: GLenum; size: int; usage: GLenum)
    {.importjs: "glCtx.bufferData(#, #, #)".}
  proc glBufferData*(target: GLenum; data: webgl.Float32Array; usage: GLenum)
    {.importjs: "glCtx.bufferData(#, #, #)".}
  proc glBufferData*(target: GLenum; data: webgl.Uint16Array; usage: GLenum)
    {.importjs: "glCtx.bufferData(#, #, #)".}
  proc glBufferData*(target: GLenum; data: webgl.Uint8Array; usage: GLenum)
    {.importjs: "glCtx.bufferData(#, #, #)".}

  proc glBufferSubData*(target: GLenum; offset: GLintptr;
      data: webgl.Float32Array)
    {.importjs: "glCtx.bufferSubData(#, #, #)".}
  proc glBufferSubData*(target: GLenum; offset: GLintptr;
      data: webgl.Uint16Array)
    {.importjs: "glCtx.bufferSubData(#, #, #)".}
  proc glBufferSubData*(target: GLenum; offset: GLintptr;
      data: webgl.Uint8Array)
    {.importjs: "glCtx.bufferSubData(#, #, #)".}

  proc glBindTexture*(target: GLenum; texture: GlTextureId)
    {.importjs: "glCtx.bindTexture(#, #)".}
  proc glActiveTexture*(texture: GLenum)
    {.importjs: "glCtx.activeTexture(#)".}

  proc glTexImage2D*(
      target: GLenum;
      level: GLint;
      internalFormat: GLint;
      width: GLsizei;
      height: GLsizei;
      border: GLint;
      format: GLenum;
      typ: GLenum;
      data: JsObject;
  ) {.importjs: "glCtx.texImage2D(#, #, #, #, #, #, #, #, #)".}

  proc glTexSubImage2D*(
      target: GLenum;
      level: GLint;
      xoffset: GLint;
      yoffset: GLint;
      width: GLsizei;
      height: GLsizei;
      format: GLenum;
      typ: GLenum;
      data: JsObject;
  ) {.importjs: "glCtx.texSubImage2D(#, #, #, #, #, #, #, #, #)".}

  proc glTexParameteri*(target: GLenum; pname: GLenum; param: GLint)
    {.importjs: "glCtx.texParameteri(#, #, #)".}
  proc glGenerateMipmap*(target: GLenum)
    {.importjs: "glCtx.generateMipmap(#)".}

  proc glBindFramebuffer*(target: GLenum; framebuffer: GlFramebufferId)
    {.importjs: "glCtx.bindFramebuffer(#, #)".}
  proc glFramebufferTexture2D*(
      target: GLenum;
      attachment: GLenum;
      textarget: GLenum;
      texture: GlTextureId;
      level: GLint;
  ) {.importjs: "glCtx.framebufferTexture2D(#, #, #, #, #)".}
  proc glCheckFramebufferStatus*(target: GLenum): GLenum
    {.importjs: "glCtx.checkFramebufferStatus(#)".}

  proc glBindVertexArray*(vao: GlVertexArrayId)
    {.importjs: "glCtx.bindVertexArray(#)".}

  proc glVertexAttribPointer*(
      index: GLuint;
      size: GLint;
      typ: GLenum;
      normalized: GLboolean;
      stride: GLsizei;
      offset: GLintptr;
  ) {.importjs: "glCtx.vertexAttribPointer(#, #, #, #, #, #)".}

  proc glVertexAttribIPointer*(
      index: GLuint;
      size: GLint;
      typ: GLenum;
      stride: GLsizei;
      offset: GLintptr;
  ) {.importjs: "glCtx.vertexAttribIPointer(#, #, #, #, #)".}

  proc glEnableVertexAttribArray*(index: GLuint)
    {.importjs: "glCtx.enableVertexAttribArray(#)".}

  proc glDrawElements*(mode: GLenum; count: GLsizei; typ: GLenum;
      offset: GLintptr)
    {.importjs: "glCtx.drawElements(#, #, #, #)".}

  proc glViewport*(x, y: GLint; width, height: GLsizei)
    {.importjs: "glCtx.viewport(#, #, #, #)".}
  proc glClearColor*(r, g, b, a: GLclampf)
    {.importjs: "glCtx.clearColor(#, #, #, #)".}
  proc glClear*(mask: GLbitfield)
    {.importjs: "glCtx.clear(#)".}

  proc glEnable*(cap: GLenum) {.importjs: "glCtx.enable(#)".}
  proc glDisable*(cap: GLenum) {.importjs: "glCtx.disable(#)".}
  proc glBlendFunc*(sfactor, dfactor: GLenum)
    {.importjs: "glCtx.blendFunc(#, #)".}
  proc glBlendFuncSeparate*(srcRGB, dstRGB, srcAlpha, dstAlpha: GLenum)
    {.importjs: "glCtx.blendFuncSeparate(#, #, #, #)".}
  proc glDepthMask*(flag: GLboolean)
    {.importjs: "glCtx.depthMask(#)".}
  proc glDepthFunc*(mode: GLenum)
    {.importjs: "glCtx.depthFunc(#)".}

  proc glGetError*(): GLenum {.importjs: "glCtx.getError()".}
  proc glGetInteger*(pname: GLenum): GLint
    {.importjs: "glCtx.getParameter(#)".}
  proc glGetString*(pname: GLenum): cstring
    {.importjs: "glCtx.getParameter(#)".}

  proc glBindBufferBase*(target: GLenum; index: GLuint; buffer: GlBufferId)
    {.importjs: "glCtx.bindBufferBase(#, #, #)".}
  proc glGetUniformBlockIndex*(program: GlProgramId; name: cstring): GLuint
    {.importjs: "glCtx.getUniformBlockIndex(#, #)".}
  proc glUniformBlockBinding*(program: GlProgramId; index: GLuint;
      binding: GLuint)
    {.importjs: "glCtx.uniformBlockBinding(#, #, #)".}

else:
  import pkg/opengl as opengl
  export opengl

  type
    GlBufferId* = GLuint
    GlTextureId* = GLuint
    GlProgramId* = GLuint
    GlShaderId* = GLuint
    GlVertexArrayId* = GLuint
    GlFramebufferId* = GLuint
    GlUniformLocation* = GLint
