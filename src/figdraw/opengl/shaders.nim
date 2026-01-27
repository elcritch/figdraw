import buffers, glapi, os, strformat, strutils, vmath, macros
import ../utils/logging

type
  ShaderCompilationError* = object of CatchableError

  ShaderAttrib = object
    name: string
    location: GLint

  Uniform = object
    name: string
    componentType: GLenum
    kind: BufferKind
    when defined(js):
      valuesI: array[16, int32]
      valuesF: array[16, float32]
    else:
      values: array[64, uint8]
    location: GlUniformLocation
    changed: bool # Flag for if this uniform has changed since last bound.

  Shader* = ref object
    paths: seq[string]
    programId*: GlProgramId
    attribs*: seq[ShaderAttrib]
    uniforms*: seq[Uniform]

when not defined(js):
  proc getErrorLog*(
      id: GlProgramId,
      path: string,
      lenProc: typeof(glGetShaderiv),
      strProc: typeof(glGetShaderInfoLog),
  ): string =
    ## Gets the error log from compiling or linking shaders.
    var length: GLint = 0
    lenProc(id, GL_INFO_LOG_LENGTH, length.addr)
    var log = newString(length.int)
    strProc(id, length, nil, cstring(log))
    when defined(emscripten):
      result = log
    else:
      if log.startsWith("Compute info"):
        log = log[25 ..^ 1]
      let clickable = &"{path}({log[2..log.find(')')]}"
      result = &"{clickable}: {log}"

when not defined(js):
  proc compileComputeShader*(compute: (string, string)): GlProgramId =
    ## Compiles the compute shader and returns the program id.
    var computeShader: GlShaderId

    block:
      var computeShaderArray = allocCStringArray([compute[1]])
      defer:
        dealloc(computeShaderArray)

      var isCompiled: GLint

      computeShader = glCreateShader(GL_COMPUTE_SHADER)
      glShaderSource(computeShader, 1, computeShaderArray, nil)
      glCompileShader(computeShader)
      glGetShaderiv(computeShader, GL_COMPILE_STATUS, isCompiled.addr)

      if isCompiled == 0:
        error "Compute shader compilation failed:",
          logs = getErrorLog(computeShader, compute[0], glGetShaderiv,
            glGetShaderInfoLog)
        quit(22)

    result = glCreateProgram()
    glAttachShader(result, computeShader)

    glLinkProgram(result)

    var isLinked: GLint
    glGetProgramiv(result, GL_LINK_STATUS, isLinked.addr)
    if isLinked == 0:
      let logs = getErrorLog(result, compute[0], glGetProgramiv, glGetProgramInfoLog)
      error "Linking compute shader failed:", logs = logs
      quit(33)

  proc compileComputeShader*(path: string): GlProgramId =
    ## Compiles the compute shader and returns the program id.
    compileComputeShader((path, readFile(path)))
else:
  proc compileComputeShader*(compute: (string, string)): GlProgramId =
    raise newException(ShaderCompilationError, "Compute shaders not supported on JS")

  proc compileComputeShader*(path: string): GlProgramId =
    raise newException(ShaderCompilationError, "Compute shaders not supported on JS")

when defined(js):
  proc compileShaderFiles*(vert, frag: (string, string)): GlProgramId =
    ## Compiles the shader files and links them into a program, returning that id.
    let vertShader = glCreateShader(GL_VERTEX_SHADER)
    glShaderSource(vertShader, cstring(vert[1]))
    glCompileShader(vertShader)
    if not glGetShaderParameter(vertShader, GL_COMPILE_STATUS):
      let logs = glGetShaderInfoLog(vertShader)
      error "Vertex shader compilation failed:", logs = logs
      quit(33)

    let fragShader = glCreateShader(GL_FRAGMENT_SHADER)
    glShaderSource(fragShader, cstring(frag[1]))
    glCompileShader(fragShader)
    if not glGetShaderParameter(fragShader, GL_COMPILE_STATUS):
      let logs = glGetShaderInfoLog(fragShader)
      error "Fragment shader compilation failed:", logs = logs
      quit(33)

    result = glCreateProgram()
    glAttachShader(result, vertShader)
    glAttachShader(result, fragShader)
    glLinkProgram(result)

    if glGetProgramParameter(result, GL_LINK_STATUS) == 0:
      let logs = glGetProgramInfoLog(result)
      error "Linking shaders failed:", logs = logs
      quit(44)
else:
  proc compileShaderFiles*(vert, frag: (string, string)): GlProgramId =
    ## Compiles the shader files and links them into a program, returning that id.
    var vertShader, fragShader: GlShaderId

    # Compile the shaders
    block shaders:
      var vertShaderArray = allocCStringArray([vert[1]])
      var fragShaderArray = allocCStringArray([frag[1]])

      defer:
        dealloc(vertShaderArray)
        dealloc(fragShaderArray)

      var isCompiled: GLint

      vertShader = glCreateShader(GL_VERTEX_SHADER)
      glShaderSource(vertShader, 1, vertShaderArray, nil)
      glCompileShader(vertShader)
      glGetShaderiv(vertShader, GL_COMPILE_STATUS, isCompiled.addr)

      if isCompiled == 0:
        let logs = getErrorLog(vertShader, vert[0], glGetShaderiv, glGetShaderInfoLog)
        if "GLSL 3.30 is not supported" in logs:
          warn "Vertex shader compilation failed",
            reason = "GLSL 3.30 is not supported",
            advice = "Try compiling with `-d:useOpenGlEs`"
          raise newException(ShaderCompilationError, "Vertex shader compilation failed")
        else:
          error "Vertex shader compilation failed:", logs = logs
          quit(33)

      fragShader = glCreateShader(GL_FRAGMENT_SHADER)
      glShaderSource(fragShader, 1, fragShaderArray, nil)
      glCompileShader(fragShader)
      glGetShaderiv(fragShader, GL_COMPILE_STATUS, isCompiled.addr)

      if isCompiled == 0:
        let logs = getErrorLog(fragShader, frag[0], glGetShaderiv, glGetShaderInfoLog)
        error "Fragment shader compilation failed:", logs = logs
        quit(33)

    # Attach shaders to a GL program
    result = glCreateProgram()
    glAttachShader(result, vertShader)
    glAttachShader(result, fragShader)

    glLinkProgram(result)

    var isLinked: GLint
    glGetProgramiv(result, GL_LINK_STATUS, isLinked.addr)
    if isLinked == 0:
      let logs = getErrorLog(result, "", glGetProgramiv, glGetProgramInfoLog)
      error "Linking shaders failed:", logs = logs
      quit(44)

proc compileShaderFiles*(vertPath, fragPath: string): GlProgramId =
  ## Compiles the shader files and links them into a program, returning that id.
  compileShaderFiles((vertPath, readFile(vertPath)), (fragPath, readFile(fragPath)))

proc readAttribsAndUniforms(shader: Shader) =
  when defined(js):
    block attributes:
      let activeAttribCount =
        glGetProgramParameter(shader.programId, GL_ACTIVE_ATTRIBUTES)

      for i in 0 ..< activeAttribCount:
        let info = glGetActiveAttrib(shader.programId, i.GLuint)
        if info.isNil:
          continue
        let name = $info.name
        let location = glGetAttribLocation(shader.programId, info.name)
        shader.attribs.add(ShaderAttrib(name: name, location: location))

    block uniforms:
      let activeUniformCount =
        glGetProgramParameter(shader.programId, GL_ACTIVE_UNIFORMS)

      for i in 0 ..< activeUniformCount:
        let info = glGetActiveUniform(shader.programId, i.GLuint)
        if info.isNil:
          continue
        let name = $info.name
        if name.endsWith("[0]"):
          continue
        let location = glGetUniformLocation(shader.programId, info.name)
        shader.uniforms.add(Uniform(name: name, location: location))
  else:
    block attributes:
      var activeAttribCount: GLint
      glGetProgramiv(shader.programId, GL_ACTIVE_ATTRIBUTES,
          activeAttribCount.addr)

      for i in 0 ..< activeAttribCount:
        var
          buf = newString(64)
          length, size: GLint
          kind: GLenum
        glGetActiveAttrib(
          shader.programId,
          i.GLuint,
          len(buf).GLint,
          length.addr,
          size.addr,
          kind.addr,
          cstring(buf),
        )
        buf.setLen(length)

        let location = glGetAttribLocation(shader.programId, cstring(buf))
        shader.attribs.add(ShaderAttrib(name: move(buf), location: location))

    block uniforms:
      var activeUniformCount: GLint
      glGetProgramiv(shader.programId, GL_ACTIVE_UNIFORMS,
          activeUniformCount.addr)

      for i in 0 ..< activeUniformCount:
        var
          buf = newString(64)
          length, size: GLint
          kind: GLenum
        glGetActiveUniform(
          shader.programId,
          i.GLuint,
          len(buf).GLint,
          length.addr,
          size.addr,
          kind.addr,
          cstring(buf),
        )
        buf.setLen(length)

        if buf.endsWith("[0]"):
          # Skip arrays, these are part of UBOs and done a different way
          continue

        let location = glGetUniformLocation(shader.programId, cstring(buf))
        shader.uniforms.add(Uniform(name: move(buf), location: location))

proc newShader*(compute: (string, string)): Shader =
  result = Shader()
  result.paths = @[compute[0]]
  result.programId = compileComputeShader(compute)
  result.readAttribsAndUniforms()

proc newShader*(computePath: string): Shader =
  let
    computeCode = readFile(computePath)
    dir = getCurrentDir()
    computePathFull = dir / computePath
  newShader((computePathFull, computeCode))

template newShaderStatic*(computePath: string): Shader =
  ## Creates a new shader but also statically reads computePath
  ## so it is compiled into the binary.
  const
    computeCode = staticRead(computePath)
    dir = getProjectPath()
    computePathFull = dir / computePath
  newShader((computePathFull, computeCode))

proc newShader*(vert, frag: (string, string)): Shader =
  result = Shader()
  result.paths = @[vert[0], frag[0]]
  result.programId = compileShaderFiles(vert, frag)
  result.readAttribsAndUniforms()

proc newShader*(vertPath, fragPath: string): Shader =
  let
    vertCode = readFile(vertPath)
    fragCode = readFile(fragPath)
    dir = getCurrentDir()
    vertPathFull = dir / vertPath
    fragPathFull = dir / fragPath
  newShader((vertPathFull, vertCode), (fragPathFull, fragCode))

template newShaderStatic*(vertPath, fragPath: string): Shader =
  ## Creates a new shader but also statically reads vertPath and fragPath
  ## so they are compiled into the binary.
  const
    vertCode = staticRead(vertPath)
    fragCode = staticRead(fragPath)
    dir = getProjectPath()
    vertPathFull = dir / vertPath
    fragPathFull = dir / fragPath
  newShader((vertPathFull, vertCode), (fragPathFull, fragCode))

proc hasUniform*(shader: Shader, name: string): bool =
  for uniform in shader.uniforms:
    if uniform.name == name:
      return true
  return false

when not defined(js):
  proc setUniform(
      shader: Shader,
      name: string,
      componentType: GLenum,
      kind: BufferKind,
      values: array[64, uint8],
  ) =
    for uniform in shader.uniforms.mitems:
      if uniform.name == name:
        if uniform.componentType != componentType or uniform.kind != kind or
            uniform.values != values:
          uniform.componentType = componentType
          uniform.kind = kind
          uniform.values = values
          uniform.changed = true
        return

    warn "Ignoring setUniform, not active", name = $name

proc setUniform(
    shader: Shader,
    name: string,
    componentType: GLenum,
    kind: BufferKind,
    values: array[16, float32],
) =
  assert componentType == cGL_FLOAT
  when defined(js):
    for uniform in shader.uniforms.mitems:
      if uniform.name == name:
        if uniform.componentType != componentType or uniform.kind != kind or
            uniform.valuesF != values:
          uniform.componentType = componentType
          uniform.kind = kind
          uniform.valuesF = values
          uniform.changed = true
        return
    warn "Ignoring setUniform, not active", name = $name
  else:
    setUniform(shader, name, componentType, kind, cast[array[64, uint8]](values))

proc setUniform(
    shader: Shader,
    name: string,
    componentType: GLenum,
    kind: BufferKind,
    values: array[16, int32],
) =
  assert componentType == cGL_INT
  when defined(js):
    for uniform in shader.uniforms.mitems:
      if uniform.name == name:
        if uniform.componentType != componentType or uniform.kind != kind or
            uniform.valuesI != values:
          uniform.componentType = componentType
          uniform.kind = kind
          uniform.valuesI = values
          uniform.changed = true
        return
    warn "Ignoring setUniform, not active", name = $name
  else:
    setUniform(shader, name, componentType, kind, cast[array[64, uint8]](values))

proc raiseUniformVarargsException(name: string, count: int) =
  raise newException(
    Exception, &"{count} varargs is more than the maximum of 4 for \"{name}\""
  )

proc raiseUniformComponentTypeException(name: string, componentType: GLenum) =
  let hex = toHex(componentType.uint32)
  raise
    newException(Exception, &"Uniform \"{name}\" is of unexpected component type {hex}")

proc raiseUniformKindException(name: string, kind: BufferKind) =
  raise newException(Exception, &"Uniform \"{name}\" is of unexpected kind {kind}")

proc setUniform*(shader: Shader, name: string, args: varargs[int32]) =
  var values: array[16, int32]
  for i in 0 ..< min(len(args), 16):
    values[i] = args[i]

  var kind: BufferKind
  case len(args)
  of 1:
    kind = bkSCALAR
  of 2:
    kind = bkVEC2
  of 3:
    kind = bkVEC3
  of 4:
    kind = bkVEC4
  else:
    raiseUniformVarargsException(name, len(args))

  shader.setUniform(name, cGL_INT, kind, values)

proc setUniform*(shader: Shader, name: string, args: varargs[float32]) =
  var values: array[16, float32]
  for i in 0 ..< min(len(args), 16):
    values[i] = args[i]

  var kind: BufferKind
  case len(args)
  of 1:
    kind = bkSCALAR
  of 2:
    kind = bkVEC2
  of 3:
    kind = bkVEC3
  of 4:
    kind = bkVEC4
  else:
    raiseUniformVarargsException(name, len(args))

  shader.setUniform(name, cGL_FLOAT, kind, values)

proc setUniform*(shader: Shader, name: string, v: Vec3) =
  var values: array[16, float32]
  values[0] = v.x
  values[1] = v.y
  values[2] = v.z
  shader.setUniform(name, cGL_FLOAT, bkVEC3, values)

proc setUniform*(shader: Shader, name: string, v: Vec4) =
  var values: array[16, float32]
  values[0] = v.x
  values[1] = v.y
  values[2] = v.z
  values[3] = v.w
  shader.setUniform(name, cGL_FLOAT, bkVEC4, values)

proc setUniform*(shader: Shader, name: string, m: Mat4) =
  when defined(js):
    var values: array[16, float32]
    when compiles(m.arr):
      for i in 0 .. 15:
        values[i] = m.arr[i]
    else:
      var idx = 0
      for r in 0 .. 3:
        for c in 0 .. 3:
          values[idx] = m[r, c]
          inc idx
    shader.setUniform(name, cGL_FLOAT, bkMAT4, values)
  else:
    shader.setUniform(name, cGL_FLOAT, bkMAT4, cast[array[16, float32]](m))

proc setUniform*(shader: Shader, name: string, b: bool) =
  var values: array[16, int32]
  values[0] = b.int32
  shader.setUniform(name, cGL_INT, bkSCALAR, values)

proc bindUniforms*(shader: Shader) =
  for uniform in shader.uniforms.mitems:
    if uniform.componentType == 0.GLenum:
      continue

    if not uniform.changed:
      continue

    if uniform.componentType == cGL_INT:
      when defined(js):
        let values = uniform.valuesI
      else:
        let values = cast[array[16, GLint]](uniform.values)
      case uniform.kind
      of bkSCALAR:
        glUniform1i(uniform.location, values[0])
      of bkVEC2:
        glUniform2i(uniform.location, values[0], values[1])
      of bkVEC3:
        glUniform3i(uniform.location, values[0], values[1], values[2])
      of bkVEC4:
        glUniform4i(uniform.location, values[0], values[1], values[2], values[3])
      else:
        raiseUniformKindException(uniform.name, uniform.kind)
    elif uniform.componentType == cGL_FLOAT:
      when defined(js):
        let values = uniform.valuesF
      else:
        let values = cast[array[16, float32]](uniform.values)
      case uniform.kind
      of bkSCALAR:
        glUniform1f(uniform.location, values[0])
      of bkVEC2:
        glUniform2f(uniform.location, values[0], values[1])
      of bkVEC3:
        glUniform3f(uniform.location, values[0], values[1], values[2])
      of bkVEC4:
        glUniform4f(uniform.location, values[0], values[1], values[2], values[3])
      of bkMAT4:
        when defined(js):
          glUniformMatrix4fv(uniform.location, 1, GL_FALSE, values)
        else:
          glUniformMatrix4fv(uniform.location, 1, GL_FALSE, values[0].unsafeAddr)
      else:
        raiseUniformKindException(uniform.name, uniform.kind)
    else:
      raiseUniformComponentTypeException(uniform.name, uniform.componentType)

    uniform.changed = false

proc bindUniformBuffer*(shader: Shader, name: string, buffer: Buffer,
    binding: GLuint) =
  assert buffer.target == GL_UNIFORM_BUFFER
  let index = glGetUniformBlockIndex(shader.programId, name)
  glBindBufferBase(GL_UNIFORM_BUFFER, binding, buffer.bufferId)
  glUniformBlockBinding(shader.programId, index, binding)

proc bindAttrib*(shader: Shader, name: string, buffer: Buffer) =
  glBindBuffer(buffer.target, buffer.bufferId)

  for attrib in shader.attribs:
    if name == attrib.name:
      if buffer.componentType == cGL_FLOAT or buffer.normalized or
          buffer.kind != bkSCALAR:
        when defined(js):
          glVertexAttribPointer(
            attrib.location.GLuint,
            int32(buffer.kind.componentCount()),
            buffer.componentType,
            if buffer.normalized: GL_TRUE else: GL_FALSE,
            0,
            0.GLintptr,
          )
        else:
          glVertexAttribPointer(
            attrib.location.GLuint,
            buffer.kind.componentCount().GLint,
            buffer.componentType,
            if buffer.normalized: GL_TRUE else: GL_FALSE,
            0,
            nil,
          )
      else:
        when defined(js):
          glVertexAttribIPointer(
            attrib.location.GLuint,
            int32(buffer.kind.componentCount()),
            buffer.componentType,
            0,
            0.GLintptr,
          )
        else:
          glVertexAttribIPointer(
            attrib.location.GLuint,
            buffer.kind.componentCount().GLint,
            buffer.componentType,
            0,
            nil,
          )

      glEnableVertexAttribArray(attrib.location.GLuint)
      return

  warn "Attribute not found in shader", name = name, shader = shader.paths
