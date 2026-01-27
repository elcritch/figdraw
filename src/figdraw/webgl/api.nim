when not defined(js) and not defined(nimsuggest):
  {.fatal: "figdraw/webgl/api requires the Nim JS backend.".}

import std/[dom, jsffi]

type
  GLenum* = uint32
  GLboolean* = bool
  GLbitfield* = uint32
  GLbyte* = int8
  GLshort* = int16
  GLint* = int32
  GLsizei* = int32
  # WebGL expects numeric byte offsets; keep these 32-bit to avoid JS BigInt.
  GLintptr* = int32
  GLsizeiptr* = int32
  GLubyte* = uint8
  GLushort* = uint16
  GLuint* = uint32
  GLfloat* = float32
  GLclampf* = float32
  GLint64* = int64
  GLuint64* = uint64

type
  WebGLRenderingContext* {.importc.} = ref object of JsRoot
  WebGL2RenderingContext* {.importc.} = ref object of WebGLRenderingContext
  WebGLActiveInfo* {.importc.} = ref object of JsRoot
  WebGLBuffer* {.importc.} = ref object of JsRoot
  WebGLContextEvent* {.importc.} = ref object of Event
  WebGLFramebuffer* {.importc.} = ref object of JsRoot
  WebGLProgram* {.importc.} = ref object of JsRoot
  WebGLQuery* {.importc.} = ref object of JsRoot
  WebGLRenderbuffer* {.importc.} = ref object of JsRoot
  WebGLSampler* {.importc.} = ref object of JsRoot
  WebGLShader* {.importc.} = ref object of JsRoot
  WebGLShaderPrecisionFormat* {.importc.} = ref object of JsRoot
  WebGLSync* {.importc.} = ref object of JsRoot
  WebGLTexture* {.importc.} = ref object of JsRoot
  WebGLTransformFeedback* {.importc.} = ref object of JsRoot
  WebGLUniformLocation* {.importc.} = ref object of JsRoot
  WebGLVertexArrayObject* {.importc.} = ref object of JsRoot

  HTMLCanvasElement* {.importc.} = ref object of Element
    width*: int
    height*: int

  Float32Array* {.importc.} = ref object of JsRoot
  Uint16Array* {.importc.} = ref object of JsRoot
  Uint32Array* {.importc.} = ref object of JsRoot

type
  WebGLExtension* = ref object of JsRoot
  AngleInstancedArrays* = WebGLExtension
  ExtBlendMinmax* = WebGLExtension
  ExtColorBufferFloat* = WebGLExtension
  ExtColorBufferHalfFloat* = WebGLExtension
  ExtDisjointTimerQuery* = WebGLExtension
  ExtFloatBlend* = WebGLExtension
  ExtFragDepth* = WebGLExtension
  ExtShaderTextureLod* = WebGLExtension
  ExtSRgb* = WebGLExtension
  ExtTextureCompressionBptc* = WebGLExtension
  ExtTextureCompressionRgtc* = WebGLExtension
  ExtTextureFilterAnisotropic* = WebGLExtension
  ExtTextureNorm16* = WebGLExtension
  KhrParallelShaderCompile* = WebGLExtension
  OesElementIndexUint* = WebGLExtension
  OesFboRenderMipmap* = WebGLExtension
  OesStandardDerivatives* = WebGLExtension
  OesTextureFloat* = WebGLExtension
  OesTextureFloatLinear* = WebGLExtension
  OesTextureHalfFloat* = WebGLExtension
  OesTextureHalfFloatLinear* = WebGLExtension
  OesVertexArrayObject* = WebGLExtension
  OvrMultiview2* = WebGLExtension
  WebglColorBufferFloat* = WebGLExtension
  WebglCompressedTextureAstc* = WebGLExtension
  WebglCompressedTextureEtc* = WebGLExtension
  WebglCompressedTextureEtc1* = WebGLExtension
  WebglCompressedTexturePvrtc* = WebGLExtension
  WebglCompressedTextureS3tc* = WebGLExtension
  WebglCompressedTextureS3tcSrgb* = WebGLExtension
  WebglDebugRendererInfo* = WebGLExtension
  WebglDebugShaders* = WebGLExtension
  WebglDepthTexture* = WebGLExtension
  WebglDrawBuffers* = WebGLExtension
  WebglLoseContext* = WebGLExtension
  WebglMultiDraw* = WebGLExtension

const
  webglContextLost* = "webglcontextlost"
  webglContextRestored* = "webglcontextrestored"
  webglContextCreationError* = "webglcontextcreationerror"

  extAngleInstancedArrays* = "ANGLE_instanced_arrays"
  extBlendMinmax* = "EXT_blend_minmax"
  extColorBufferFloat* = "EXT_color_buffer_float"
  extColorBufferHalfFloat* = "EXT_color_buffer_half_float"
  extDisjointTimerQuery* = "EXT_disjoint_timer_query"
  extFloatBlend* = "EXT_float_blend"
  extFragDepth* = "EXT_frag_depth"
  extShaderTextureLod* = "EXT_shader_texture_lod"
  extSRgb* = "EXT_sRGB"
  extTextureCompressionBptc* = "EXT_texture_compression_bptc"
  extTextureCompressionRgtc* = "EXT_texture_compression_rgtc"
  extTextureFilterAnisotropic* = "EXT_texture_filter_anisotropic"
  extTextureNorm16* = "EXT_texture_norm16"
  khrParallelShaderCompile* = "KHR_parallel_shader_compile"
  oesElementIndexUint* = "OES_element_index_uint"
  oesFboRenderMipmap* = "OES_fbo_render_mipmap"
  oesStandardDerivatives* = "OES_standard_derivatives"
  oesTextureFloat* = "OES_texture_float"
  oesTextureFloatLinear* = "OES_texture_float_linear"
  oesTextureHalfFloat* = "OES_texture_half_float"
  oesTextureHalfFloatLinear* = "OES_texture_half_float_linear"
  oesVertexArrayObject* = "OES_vertex_array_object"
  ovrMultiview2* = "OVR_multiview2"
  webglColorBufferFloat* = "WEBGL_color_buffer_float"
  webglCompressedTextureAstc* = "WEBGL_compressed_texture_astc"
  webglCompressedTextureEtc* = "WEBGL_compressed_texture_etc"
  webglCompressedTextureEtc1* = "WEBGL_compressed_texture_etc1"
  webglCompressedTexturePvrtc* = "WEBGL_compressed_texture_pvrtc"
  webglCompressedTextureS3tc* = "WEBGL_compressed_texture_s3tc"
  webglCompressedTextureS3tcSrgb* = "WEBGL_compressed_texture_s3tc_srgb"
  webglDebugRendererInfo* = "WEBGL_debug_renderer_info"
  webglDebugShaders* = "WEBGL_debug_shaders"
  webglDepthTexture* = "WEBGL_depth_texture"
  webglDrawBuffers* = "WEBGL_draw_buffers"
  webglLoseContext* = "WEBGL_lose_context"
  webglMultiDraw* = "WEBGL_multi_draw"

  ARRAY_BUFFER* = 0x8892.GLenum
  STATIC_DRAW* = 0x88E4.GLenum
  FLOAT* = 0x1406.GLenum
  TRIANGLES* = 0x0004.GLenum
  COLOR_BUFFER_BIT* = 0x4000.GLenum
  VERTEX_SHADER* = 0x8B31.GLenum
  FRAGMENT_SHADER* = 0x8B30.GLenum
  COMPILE_STATUS* = 0x8B81.GLenum
  LINK_STATUS* = 0x8B82.GLenum

proc asCanvas*(el: Element): HTMLCanvasElement =
  cast[HTMLCanvasElement](el)

proc newFloat32Array*(data: openArray[float32]): Float32Array
  {.importjs: "new Float32Array(#)".}

proc newUint16Array*(data: openArray[uint16]): Uint16Array
  {.importjs: "new Uint16Array(#)".}

proc newUint32Array*(data: openArray[uint32]): Uint32Array
  {.importjs: "new Uint32Array(#)".}

proc getContext*(canvas: HTMLCanvasElement;
    contextId: cstring): WebGLRenderingContext
  {.importjs: "#.getContext(#)".}

proc getContext*(canvas: HTMLCanvasElement; contextId: cstring;
    options: JsObject): WebGLRenderingContext
  {.importjs: "#.getContext(#, #)".}

proc getExtension*(gl: WebGLRenderingContext; name: cstring): WebGLExtension
  {.importjs: "#.getExtension(#)".}

proc isContextLost*(gl: WebGLRenderingContext): bool
  {.importjs: "#.isContextLost()".}

proc statusMessage*(ev: WebGLContextEvent): cstring
  {.importjs: "#.statusMessage".}

proc canvas*(gl: WebGLRenderingContext): HTMLCanvasElement
  {.importjs: "#.canvas".}

proc drawingBufferWidth*(gl: WebGLRenderingContext): int
  {.importjs: "#.drawingBufferWidth".}

proc drawingBufferHeight*(gl: WebGLRenderingContext): int
  {.importjs: "#.drawingBufferHeight".}

proc createShader*(gl: WebGLRenderingContext; shaderType: GLenum): WebGLShader
  {.importjs: "#.createShader(#)".}

proc shaderSource*(gl: WebGLRenderingContext; shader: WebGLShader;
    source: cstring)
  {.importjs: "#.shaderSource(#, #)".}

proc compileShader*(gl: WebGLRenderingContext; shader: WebGLShader)
  {.importjs: "#.compileShader(#)".}

proc getShaderParameter*(gl: WebGLRenderingContext; shader: WebGLShader;
    pname: GLenum): bool
  {.importjs: "#.getShaderParameter(#, #)".}

proc getShaderInfoLog*(gl: WebGLRenderingContext; shader: WebGLShader): cstring
  {.importjs: "#.getShaderInfoLog(#)".}

proc deleteShader*(gl: WebGLRenderingContext; shader: WebGLShader)
  {.importjs: "#.deleteShader(#)".}

proc createProgram*(gl: WebGLRenderingContext): WebGLProgram
  {.importjs: "#.createProgram()".}

proc attachShader*(gl: WebGLRenderingContext; program: WebGLProgram;
    shader: WebGLShader)
  {.importjs: "#.attachShader(#, #)".}

proc linkProgram*(gl: WebGLRenderingContext; program: WebGLProgram)
  {.importjs: "#.linkProgram(#)".}

proc getProgramParameter*(gl: WebGLRenderingContext; program: WebGLProgram;
    pname: GLenum): bool
  {.importjs: "#.getProgramParameter(#, #)".}

proc getProgramInfoLog*(gl: WebGLRenderingContext;
    program: WebGLProgram): cstring
  {.importjs: "#.getProgramInfoLog(#)".}

proc deleteProgram*(gl: WebGLRenderingContext; program: WebGLProgram)
  {.importjs: "#.deleteProgram(#)".}

proc useProgram*(gl: WebGLRenderingContext; program: WebGLProgram)
  {.importjs: "#.useProgram(#)".}

proc getAttribLocation*(gl: WebGLRenderingContext; program: WebGLProgram;
    name: cstring): GLint
  {.importjs: "#.getAttribLocation(#, #)".}

proc enableVertexAttribArray*(gl: WebGLRenderingContext; index: GLint)
  {.importjs: "#.enableVertexAttribArray(#)".}

proc vertexAttribPointer*(
    gl: WebGLRenderingContext;
    index: GLint;
    size: GLint;
    typ: GLenum;
    normalized: bool;
    stride: GLsizei;
    offset: GLintptr;
) {.importjs: "#.vertexAttribPointer(#, #, #, #, #, #)".}

proc getUniformLocation*(
    gl: WebGLRenderingContext;
    program: WebGLProgram;
    name: cstring;
): WebGLUniformLocation {.importjs: "#.getUniformLocation(#, #)".}

proc uniform2f*(
    gl: WebGLRenderingContext;
    location: WebGLUniformLocation;
    v0: GLfloat;
    v1: GLfloat;
) {.importjs: "#.uniform2f(#, #, #)".}

proc createBuffer*(gl: WebGLRenderingContext): WebGLBuffer
  {.importjs: "#.createBuffer()".}

proc bindBuffer*(gl: WebGLRenderingContext; target: GLenum; buffer: WebGLBuffer)
  {.importjs: "#.bindBuffer(#, #)".}

proc bufferData*(gl: WebGLRenderingContext; target: GLenum; data: Float32Array; usage: GLenum)
  {.importjs: "#.bufferData(#, #, #)".}

proc deleteBuffer*(gl: WebGLRenderingContext; buffer: WebGLBuffer)
  {.importjs: "#.deleteBuffer(#)".}

proc clearColor*(gl: WebGLRenderingContext; r, g, b, a: GLclampf)
  {.importjs: "#.clearColor(#, #, #, #)".}

proc clear*(gl: WebGLRenderingContext; mask: GLbitfield)
  {.importjs: "#.clear(#)".}

proc viewport*(gl: WebGLRenderingContext; x, y: GLint; width, height: GLsizei)
  {.importjs: "#.viewport(#, #, #, #)".}

proc drawArrays*(gl: WebGLRenderingContext; mode: GLenum; first: GLint;
    count: GLsizei)
  {.importjs: "#.drawArrays(#, #, #)".}
