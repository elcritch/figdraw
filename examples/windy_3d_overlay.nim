when defined(emscripten):
  import std/[times, math, strformat]
else:
  import std/[os, times, math, strformat]
import chroma

when not UseMetalBackend:
  import pkg/opengl

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer
when not UseMetalBackend:
  import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

when not UseMetalBackend:
  type PyramidGl = object
    program: GLuint
    vao: GLuint
    vbo: GLuint
    ebo: GLuint
    mvpLoc: GLint
    indexCount: GLsizei

type
  PyramidShaderError = object of CatchableError
  Vec3f = object
    x: float32
    y: float32
    z: float32

  Vec4f = object
    x: float32
    y: float32
    z: float32
    w: float32

  Mat4 = array[16, float32] # Column-major for OpenGL uniforms.

proc v3(x, y, z: float32): Vec3f =
  Vec3f(x: x, y: y, z: z)

proc v3Sub(a, b: Vec3f): Vec3f =
  v3(a.x - b.x, a.y - b.y, a.z - b.z)

proc v3Dot(a, b: Vec3f): float32 =
  a.x * b.x + a.y * b.y + a.z * b.z

proc v3Cross(a, b: Vec3f): Vec3f =
  v3(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)

proc v4(x, y, z, w: float32): Vec4f =
  Vec4f(x: x, y: y, z: z, w: w)

proc v3Normalize(v: Vec3f): Vec3f =
  let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
  if len <= 0.0'f32:
    return v3(0.0'f32, 0.0'f32, 0.0'f32)
  let inv = 1.0'f32 / len
  v3(v.x * inv, v.y * inv, v.z * inv)

proc mat4Mul(a, b: Mat4): Mat4 =
  for col in 0 .. 3:
    for row in 0 .. 3:
      result[col * 4 + row] =
        a[0 * 4 + row] * b[col * 4 + 0] + a[1 * 4 + row] * b[col * 4 + 1] +
        a[2 * 4 + row] * b[col * 4 + 2] + a[3 * 4 + row] * b[col * 4 + 3]

proc mat4MulVec4(m: Mat4, v: Vec4f): Vec4f =
  result.x = m[0] * v.x + m[4] * v.y + m[8] * v.z + m[12] * v.w
  result.y = m[1] * v.x + m[5] * v.y + m[9] * v.z + m[13] * v.w
  result.z = m[2] * v.x + m[6] * v.y + m[10] * v.z + m[14] * v.w
  result.w = m[3] * v.x + m[7] * v.y + m[11] * v.z + m[15] * v.w

proc vec4ToNdc(v: Vec4f): Vec3f =
  if v.w == 0.0'f32:
    return v3(0.0'f32, 0.0'f32, 0.0'f32)
  let inv = 1.0'f32 / v.w
  v3(v.x * inv, v.y * inv, v.z * inv)

proc mat4Perspective(fovyDeg, aspect, zNear, zFar: float32): Mat4 =
  let fovyRad = fovyDeg * (PI.float32 / 180.0'f32)
  let f = 1.0'f32 / tan(fovyRad * 0.5'f32)
  let nf = 1.0'f32 / (zNear - zFar)
  result[0] = f / aspect
  result[5] = f
  result[10] = (zFar + zNear) * nf
  result[11] = -1.0'f32
  result[14] = (2.0'f32 * zFar * zNear) * nf

proc mat4LookAt(eye, center, up: Vec3f): Mat4 =
  let f = v3Normalize(v3Sub(center, eye))
  let s = v3Normalize(v3Cross(f, up))
  let u = v3Cross(s, f)
  result[0] = s.x
  result[1] = s.y
  result[2] = s.z
  result[4] = u.x
  result[5] = u.y
  result[6] = u.z
  result[8] = -f.x
  result[9] = -f.y
  result[10] = -f.z
  result[12] = -v3Dot(s, eye)
  result[13] = -v3Dot(u, eye)
  result[14] = v3Dot(f, eye)
  result[15] = 1.0'f32

proc mat4RotateX(angle: float32): Mat4 =
  let c = cos(angle)
  let s = sin(angle)
  result[0] = 1.0'f32
  result[5] = c
  result[6] = s
  result[9] = -s
  result[10] = c
  result[15] = 1.0'f32

proc mat4RotateY(angle: float32): Mat4 =
  let c = cos(angle)
  let s = sin(angle)
  result[0] = c
  result[2] = -s
  result[5] = 1.0'f32
  result[8] = s
  result[10] = c
  result[15] = 1.0'f32

proc pyramidModelMatrix(t: float32): Mat4 =
  mat4Mul(mat4RotateY(t * 0.9'f32), mat4RotateX(-0.4'f32))

proc cameraEye(): Vec3f =
  v3(1.6'f32, 1.1'f32, 2.2'f32)

proc cameraCenter(): Vec3f =
  v3(0.0'f32, 0.25'f32, 0.0'f32)

proc viewMatrix(): Mat4 =
  mat4LookAt(cameraEye(), cameraCenter(), v3(0.0'f32, 1.0'f32, 0.0'f32))

proc projectionMatrix(frameSize: Vec2): Mat4 =
  let aspect =
    if frameSize.y > 0:
      frameSize.x / frameSize.y
    else:
      1.0'f32
  mat4Perspective(45.0'f32, aspect, 0.1'f32, 100.0'f32)

proc formatVec3(label: string, v: Vec3f): string =
  result = fmt"{label} {v.x:>7.3f} {v.y:>7.3f} {v.z:>7.3f}"

const PyramidVertexStride = 6
const PyramidVertices: array[30, float32] = [
  -0.5, 0.0, -0.5, 1.0, 0.2, 0.2, 0.5, 0.0, -0.5, 0.2, 1.0, 0.2, 0.5, 0.0, 0.5, 0.2,
  0.2, 1.0, -0.5, 0.0, 0.5, 1.0, 1.0, 0.2, 0.0, 0.8, 0.0, 1.0, 0.2, 1.0,
]
const PyramidIndices: array[18, uint16] = [
  0'u16, 1'u16, 4'u16, 1'u16, 2'u16, 4'u16, 2'u16, 3'u16, 4'u16, 3'u16, 0'u16, 4'u16,
  0'u16, 1'u16, 2'u16, 2'u16, 3'u16, 0'u16,
]

proc pyramidPosition(index: int): Vec3f =
  let base = index * PyramidVertexStride
  v3(PyramidVertices[base], PyramidVertices[base + 1], PyramidVertices[base + 2])

proc triangleInfoRows(mvp: Mat4, triIndex: int): array[4, string] =
  let base = triIndex * 3
  let idx0 = PyramidIndices[base + 0].int
  let idx1 = PyramidIndices[base + 1].int
  let idx2 = PyramidIndices[base + 2].int

  let v0 = pyramidPosition(idx0)
  let v1 = pyramidPosition(idx1)
  let v2 = pyramidPosition(idx2)
  let ndc0 = vec4ToNdc(mat4MulVec4(mvp, v4(v0.x, v0.y, v0.z, 1.0'f32)))
  let ndc1 = vec4ToNdc(mat4MulVec4(mvp, v4(v1.x, v1.y, v1.z, 1.0'f32)))
  let ndc2 = vec4ToNdc(mat4MulVec4(mvp, v4(v2.x, v2.y, v2.z, 1.0'f32)))
  let centroid = v3(
    (ndc0.x + ndc1.x + ndc2.x) / 3.0'f32,
    (ndc0.y + ndc1.y + ndc2.y) / 3.0'f32,
    (ndc0.z + ndc1.z + ndc2.z) / 3.0'f32,
  )

  result[0] = formatVec3("v0", ndc0)
  result[1] = formatVec3("v1", ndc1)
  result[2] = formatVec3("v2", ndc2)
  result[3] = formatVec3("ctr", centroid)

when not UseMetalBackend:
  proc compileShader(shaderType: GLenum, source, label: string): GLuint =
    var shaderArray = allocCStringArray([source])
    defer:
      dealloc(shaderArray)

    let shader = glCreateShader(shaderType)
    glShaderSource(shader, 1, shaderArray, nil)
    glCompileShader(shader)

    var status: GLint
    glGetShaderiv(shader, GL_COMPILE_STATUS, status.addr)
    if status == 0:
      var logLen: GLint = 0
      glGetShaderiv(shader, GL_INFO_LOG_LENGTH, logLen.addr)
      var log = newString(logLen.int)
      glGetShaderInfoLog(shader, logLen, nil, log.cstring)
      glDeleteShader(shader)
      raise newException(
        PyramidShaderError, "Shader compile failed (" & label & "): " & log
      )

    result = shader

  proc buildProgram(vertexSrc, fragmentSrc: string): GLuint =
    let vertexShader = compileShader(GL_VERTEX_SHADER, vertexSrc, "pyramid.vert")
    let fragmentShader = compileShader(GL_FRAGMENT_SHADER, fragmentSrc, "pyramid.frag")

    result = glCreateProgram()
    glAttachShader(result, vertexShader)
    glAttachShader(result, fragmentShader)
    glLinkProgram(result)

    var status: GLint
    glGetProgramiv(result, GL_LINK_STATUS, status.addr)
    if status == 0:
      var logLen: GLint = 0
      glGetProgramiv(result, GL_INFO_LOG_LENGTH, logLen.addr)
      var log = newString(logLen.int)
      glGetProgramInfoLog(result, logLen, nil, log.cstring)
      glDeleteProgram(result)
      result = 0
      glDeleteShader(vertexShader)
      glDeleteShader(fragmentShader)
      raise newException(PyramidShaderError, "Shader link failed: " & log)

    glDetachShader(result, vertexShader)
    glDetachShader(result, fragmentShader)
    glDeleteShader(vertexShader)
    glDeleteShader(fragmentShader)

proc setupWindow(frame: AppFrame, window: Window) =
  when not defined(emscripten):
    if frame.windowInfo.fullscreen:
      window.fullscreen = frame.windowInfo.fullscreen
    else:
      window.size = ivec2(frame.windowInfo.box.wh.scaled())

    window.visible = true
  when not UseMetalBackend:
    window.makeContextCurrent()

proc newWindyWindow(frame: AppFrame): Window =
  let window =
    when defined(emscripten):
      newWindow("FigDraw", ivec2(0, 0), visible = false)
    else:
      newWindow("FigDraw", ivec2(1280, 800), visible = false)
  when defined(emscripten):
    setupWindow(frame, window)
    startOpenGL(openglVersion)
  elif UseMetalBackend:
    setupWindow(frame, window)
  else:
    startOpenGL(openglVersion)
    setupWindow(frame, window)
  result = window

proc getWindowInfo(window: Window): WindowInfo =
  app.requestedFrame.inc
  result.minimized = window.minimized()
  result.pixelRatio = window.contentScale()
  let size = window.size()
  result.box.w = size.x.float32.descaled()
  result.box.h = size.y.float32.descaled()

when not UseMetalBackend:
  proc initPyramid(): PyramidGl =
    let vertexSrc =
      when defined(emscripten):
        """
#version 300 es
precision highp float;

layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aColor;

uniform mat4 uMvp;
out vec3 vColor;

void main() {
  vColor = aColor;
  gl_Position = uMvp * vec4(aPos, 1.0);
}
"""
      else:
        """
#version 330 core
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aColor;

uniform mat4 uMvp;
out vec3 vColor;

void main() {
  vColor = aColor;
  gl_Position = uMvp * vec4(aPos, 1.0);
}
"""

    let fragmentSrc =
      when defined(emscripten):
        """
#version 300 es
precision highp float;

in vec3 vColor;
out vec4 fragColor;

void main() {
  fragColor = vec4(vColor, 1.0);
}
"""
      else:
        """
#version 330 core
in vec3 vColor;
out vec4 FragColor;

void main() {
  FragColor = vec4(vColor, 1.0);
}
"""

    result.program = buildProgram(vertexSrc, fragmentSrc)
    result.mvpLoc = glGetUniformLocation(result.program, "uMvp")

    result.indexCount = PyramidIndices.len.GLsizei

    glGenVertexArrays(1, result.vao.addr)
    glGenBuffers(1, result.vbo.addr)
    glGenBuffers(1, result.ebo.addr)

    glBindVertexArray(result.vao)

    glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
    glBufferData(
      GL_ARRAY_BUFFER, sizeof(PyramidVertices), PyramidVertices[0].addr, GL_STATIC_DRAW
    )

    glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, result.ebo)
    glBufferData(
      GL_ELEMENT_ARRAY_BUFFER,
      sizeof(PyramidIndices),
      PyramidIndices[0].addr,
      GL_STATIC_DRAW,
    )

    let stride = (6 * sizeof(float32)).GLsizei
    glVertexAttribPointer(0, 3, cGL_FLOAT, GL_FALSE, stride, cast[pointer](0))
    glEnableVertexAttribArray(0)

    glVertexAttribPointer(
      1, 3, cGL_FLOAT, GL_FALSE, stride, cast[pointer](3 * sizeof(float32))
    )
    glEnableVertexAttribArray(1)

    glBindVertexArray(0)

  proc destroyPyramid(pyramid: PyramidGl) =
    if pyramid.program != 0:
      glDeleteProgram(pyramid.program)

    var vao = pyramid.vao
    if vao != 0:
      glDeleteVertexArrays(1, vao.addr)

    var vbo = pyramid.vbo
    if vbo != 0:
      glDeleteBuffers(1, vbo.addr)

    var ebo = pyramid.ebo
    if ebo != 0:
      glDeleteBuffers(1, ebo.addr)

  proc drawPyramid(pyramid: PyramidGl, frameSize: Vec2, mvp: Mat4) =
    glViewport(0, 0, frameSize.x.GLint, frameSize.y.GLint)

    glUseProgram(pyramid.program)
    glUniformMatrix4fv(pyramid.mvpLoc, 1, GL_FALSE, cast[ptr GLfloat](mvp[0].addr))
    glBindVertexArray(pyramid.vao)
    glDrawElements(GL_TRIANGLES, pyramid.indexCount, GL_UNSIGNED_SHORT, nil)
    glBindVertexArray(0)
    glUseProgram(0)

proc makeOverlay*(
    w, h: float32,
    rows: openArray[string],
    monoFont: UiFont,
    bg: Color = rgba(0, 0, 0, 0).color,
): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: bg,
    )
  )

  let pad = 24'f32
  let panelWBase = min(320'f32, w * 0.4'f32) * 1.2'f32
  let panelW = max(panelWBase, monoFont.size * 16.0'f32) * 1.15'f32
  let panelRect = rect(w - panelW - pad, pad, panelW, h - pad * 2)
  let panelShadow = RenderShadow(
    style: DropShadow, blur: 18, spread: 0, x: 0, y: 10, color: rgba(0, 0, 0, 60).color
  )

  let panelIdx = list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: panelRect,
      fill: rgba(20, 22, 32, 220).color,
      stroke: RenderStroke(weight: 1.5, color: rgba(255, 255, 255, 40).color),
      corners: [12.0'f32, 12.0, 12.0, 12.0],
      shadows: [panelShadow, RenderShadow(), RenderShadow(), RenderShadow()],
    ),
  )

  let buttonPad = 18'f32
  let buttonW = panelRect.w - buttonPad * 2
  let textPadX = max(12'f32, monoFont.size * 0.5'f32)
  let textPadY = 8'f32
  let rowGap = 12'f32
  let rowHeight = max(34'f32, monoFont.size + textPadY * 2 + 2'f32)
  var buttonY = panelRect.y + buttonPad

  for i, row in rows:
    let btnRect = rect(panelRect.x + buttonPad, buttonY, buttonW, rowHeight)
    let rowShadow = RenderShadow(
      style: DropShadow,
      blur: 6,
      spread: 0,
      x: 0,
      y: 1,
      color: rgba(255, 255, 255, 36).color,
    )
    discard list.addChild(
      panelIdx,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: btnRect,
        fill: rgba(uint8(40 + i * 8), 90'u8, 160'u8, 200'u8).color,
        corners: [8.0'f32, 8.0, 8.0, 8.0],
        shadows: [rowShadow, RenderShadow(), RenderShadow(), RenderShadow()],
      ),
    )
    let textRect = rect(
      btnRect.x + textPadX,
      btnRect.y + textPadY,
      btnRect.w - textPadX * 2,
      btnRect.h - textPadY * 2,
    )
    let rowLayout = typeset(
      rect(0, 0, textRect.w, textRect.h),
      [(monoFont, row)],
      hAlign = Left,
      vAlign = Middle,
      minContent = false,
      wrap = false,
    )
    discard list.addChild(
      panelIdx,
      Fig(
        kind: nkText,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: textRect,
        fill: rgba(240, 242, 248, 240).color,
        textLayout: rowLayout,
      ),
    )
    buttonY += rowHeight + rowGap

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  let monoTypeface = loadTypeface("HackNerdFont-Regular.ttf")
  let monoFont = monoTypeface.fontWithSize(24.0'f32)

  var frame = AppFrame(windowTitle: "figdraw: OpenGL 3D + overlay")
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, 1920, 1280),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  let window = newWindyWindow(frame)
  let renderer = glrenderer.newFigRenderer(atlasSize = 192, pixelScale = app.pixelScale)
  when UseMetalBackend:
    let metalHandle = attachMetalLayer(window, renderer.ctx.metalDevice())
    renderer.ctx.presentLayer = metalHandle.layer

  when UseMetalBackend:
    proc updateMetalLayer() =
      metalHandle.updateMetalLayer(window)

  when not UseMetalBackend:
    let pyramid = initPyramid()

  let startTime = epochTime()
  var lastFrameTime = startTime
  var fpsValue = 0.0
  let fpsAlpha = 0.15

  proc redraw() =
    when UseMetalBackend:
      updateMetalLayer()

    let now = epochTime()
    let dt = now - lastFrameTime
    if dt > 0.0:
      let instFps = 1.0 / dt
      if fpsValue <= 0.0:
        fpsValue = instFps
      else:
        fpsValue = fpsValue + (instFps - fpsValue) * fpsAlpha
    lastFrameTime = now

    let winInfo = window.getWindowInfo()
    let frameSize = winInfo.box.wh.scaled()
    var rows = newSeq[string](0)
    rows.add(fmt"fps {fpsValue:>7.2f}")
    rows.add(fmt"size {winInfo.box.w.int}x{winInfo.box.h.int}")

    when not UseMetalBackend:
      let proj = projectionMatrix(frameSize)
      let view = viewMatrix()
      let model = pyramidModelMatrix((now - startTime).float32)
      let mvp = mat4Mul(proj, mat4Mul(view, model))
      let triRows = triangleInfoRows(mvp, 0)
      for row in triRows:
        rows.add(row)

      var renders = makeOverlay(winInfo.box.w, winInfo.box.h, rows, monoFont)

      useDepthBuffer(true)
      glClearColor(0.08, 0.1, 0.14, 1.0)
      glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
      drawPyramid(pyramid, frameSize, mvp)

      useDepthBuffer(false)
      renderer.renderOverlayFrame(renders, frameSize)
      window.swapBuffers()
    else:
      var renders = makeOverlay(
        winInfo.box.w, winInfo.box.h, rows, monoFont, bg = rgba(20, 25, 36, 255).color
      )
      renderer.renderFrame(renders, frameSize)

  window.onCloseRequest = proc() =
    app.running = false
  window.onResize = proc() =
    redraw()

  try:
    while app.running:
      pollEvents()
      redraw()
      if RunOnce:
        app.running = false
  finally:
    when not UseMetalBackend:
      destroyPyramid(pyramid)
    when not defined(emscripten):
      window.close()
