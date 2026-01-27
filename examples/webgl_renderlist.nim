when not defined(js) and not defined(nimsuggest):
  {.fatal: "This example requires the Nim JS backend (nim js).".}

import std/[dom, jsconsole, jsffi]
import figdraw/webgl/api

type
  Rect = object
    x, y, w, h: float32
    color: array[4, float32]

const
  baseWidth = 800'f32
  baseHeight = 600'f32

proc rgba(r, g, b: int; a: int = 255): array[4, float32] =
  [
    r.float32 / 255'f32,
    g.float32 / 255'f32,
    b.float32 / 255'f32,
    a.float32 / 255'f32,
  ]

proc makeRenderList(width, height: float32): seq[Rect] =
  let sx = width / baseWidth
  let sy = height / baseHeight
  result = @[
    Rect(
      x: 60'f32 * sx,
      y: 60'f32 * sy,
      w: 220'f32 * sx,
      h: 140'f32 * sy,
      color: rgba(220, 40, 40),
    ),
    Rect(
      x: 320'f32 * sx,
      y: 120'f32 * sy,
      w: 220'f32 * sx,
      h: 140'f32 * sy,
      color: rgba(40, 180, 90),
    ),
    Rect(
      x: 180'f32 * sx,
      y: 300'f32 * sy,
      w: 220'f32 * sx,
      h: 140'f32 * sy,
      color: rgba(60, 90, 220),
    ),
  ]

proc appendRect(data: var seq[float32]; rect: Rect) =
  let x0 = rect.x
  let y0 = rect.y
  let x1 = rect.x + rect.w
  let y1 = rect.y + rect.h
  let c = rect.color

  data.add x0
  data.add y0
  data.add c[0]
  data.add c[1]
  data.add c[2]
  data.add c[3]

  data.add x1
  data.add y0
  data.add c[0]
  data.add c[1]
  data.add c[2]
  data.add c[3]

  data.add x0
  data.add y1
  data.add c[0]
  data.add c[1]
  data.add c[2]
  data.add c[3]

  data.add x0
  data.add y1
  data.add c[0]
  data.add c[1]
  data.add c[2]
  data.add c[3]

  data.add x1
  data.add y0
  data.add c[0]
  data.add c[1]
  data.add c[2]
  data.add c[3]

  data.add x1
  data.add y1
  data.add c[0]
  data.add c[1]
  data.add c[2]
  data.add c[3]

proc buildVertexData(rects: seq[Rect]): seq[float32] =
  result = newSeqOfCap[float32](rects.len * 6 * 6)
  for rect in rects:
    appendRect(result, rect)

proc compileShader(
    gl: WebGLRenderingContext;
    shaderType: GLenum;
    source: cstring;
): WebGLShader =
  let shader = gl.createShader(shaderType)
  if shader.isNull or shader.isUndefined:
    console.error("createShader failed")
    return nil

  gl.shaderSource(shader, source)
  gl.compileShader(shader)
  if not gl.getShaderParameter(shader, COMPILE_STATUS):
    console.error("shader compile failed:", gl.getShaderInfoLog(shader))
    gl.deleteShader(shader)
    return nil

  result = shader

proc linkProgram(
    gl: WebGLRenderingContext;
    vertexShader: WebGLShader;
    fragmentShader: WebGLShader;
): WebGLProgram =
  let program = gl.createProgram()
  if program.isNull or program.isUndefined:
    console.error("createProgram failed")
    return nil

  gl.attachShader(program, vertexShader)
  gl.attachShader(program, fragmentShader)
  gl.linkProgram(program)
  if not gl.getProgramParameter(program, LINK_STATUS):
    console.error("program link failed:", gl.getProgramInfoLog(program))
    gl.deleteProgram(program)
    return nil

  result = program

proc main() =
  let canvas = document.createElement("canvas").asCanvas
  document.body.appendChild(canvas)

  document.body.style.margin = "0"
  document.body.style.overflow = "hidden"
  document.body.style.background = "#0c0f16"
  canvas.style.display = "block"

  let gl = canvas.getContext("webgl")
  if gl.isNull or gl.isUndefined:
    console.error("WebGL not available")
    return

  let vertexSource = cstring("""
    attribute vec2 a_position;
    attribute vec4 a_color;
    uniform vec2 u_resolution;
    varying vec4 v_color;

    void main() {
      vec2 zeroToOne = a_position / u_resolution;
      vec2 zeroToTwo = zeroToOne * 2.0;
      vec2 clip = zeroToTwo - 1.0;
      gl_Position = vec4(clip * vec2(1, -1), 0.0, 1.0);
      v_color = a_color;
    }
  """)

  let fragmentSource = cstring("""
    precision mediump float;
    varying vec4 v_color;

    void main() {
      gl_FragColor = v_color;
    }
  """)

  let vertexShader = compileShader(gl, VERTEX_SHADER, vertexSource)
  let fragmentShader = compileShader(gl, FRAGMENT_SHADER, fragmentSource)
  if vertexShader.isNull or fragmentShader.isNull:
    return

  let program = linkProgram(gl, vertexShader, fragmentShader)
  if program.isNull:
    return

  let aPosition = gl.getAttribLocation(program, "a_position")
  let aColor = gl.getAttribLocation(program, "a_color")
  let uResolution = gl.getUniformLocation(program, "u_resolution")

  let vertexBuffer = gl.createBuffer()
  if vertexBuffer.isNull:
    console.error("createBuffer failed")
    return

  var lastWidth = 0
  var lastHeight = 0
  var vertexCount = 0

  proc updateGeometry(width, height: int) =
    let rects = makeRenderList(width.float32, height.float32)
    let data = buildVertexData(rects)
    vertexCount = data.len div 6
    gl.bindBuffer(ARRAY_BUFFER, vertexBuffer)
    gl.bufferData(ARRAY_BUFFER, newFloat32Array(data), STATIC_DRAW)

  proc draw(width, height: int) =
    gl.viewport(0, 0, canvas.width, canvas.height)
    gl.clearColor(1.0, 1.0, 1.0, 1.0)
    gl.clear(COLOR_BUFFER_BIT)

    gl.useProgram(program)
    gl.bindBuffer(ARRAY_BUFFER, vertexBuffer)

    let stride = GLsizei(6 * 4)
    gl.enableVertexAttribArray(aPosition)
    gl.vertexAttribPointer(aPosition, 2, FLOAT, false, stride, 0.GLintptr)
    gl.enableVertexAttribArray(aColor)
    gl.vertexAttribPointer(aColor, 4, FLOAT, false, stride, (2 * 4).GLintptr)

    gl.uniform2f(uResolution, width.float32, height.float32)
    gl.drawArrays(TRIANGLES, 0, vertexCount.GLsizei)

  proc resizeAndRender() =
    let dpr = if window.devicePixelRatio <= 0: 1.0 else: window.devicePixelRatio
    let cssWidth = max(window.innerWidth, 1)
    let cssHeight = max(window.innerHeight, 1)

    canvas.width = int(cssWidth.float * dpr)
    canvas.height = int(cssHeight.float * dpr)
    canvas.style.width = cstring($cssWidth & "px")
    canvas.style.height = cstring($cssHeight & "px")

    if cssWidth != lastWidth or cssHeight != lastHeight:
      lastWidth = cssWidth
      lastHeight = cssHeight
      updateGeometry(cssWidth, cssHeight)

    draw(cssWidth, cssHeight)

  proc onResize(e: Event) =
    resizeAndRender()

  window.addEventListener("resize", onResize)
  resizeAndRender()

when isMainModule:
  main()
