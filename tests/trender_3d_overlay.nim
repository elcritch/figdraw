import std/os
import std/unittest

import pkg/chroma
import pkg/pixie
import pkg/opengl
import pkg/vmath
import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/shaders
import figdraw/utils/glutils

import ./opengl_test_utils

type PyramidGl = object
  program: GLuint
  vao: GLuint
  vbo: GLuint
  ebo: GLuint
  mvpLoc: GLint
  indexCount: GLsizei

proc initPyramid(): PyramidGl =
  let vertexSrc = """
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

  let fragmentSrc = """
#version 330 core
in vec3 vColor;
out vec4 FragColor;

void main() {
  FragColor = vec4(vColor, 1.0);
}
"""

  result.program =
    compileShaderFiles(("pyramid.vert", vertexSrc), ("pyramid.frag", fragmentSrc))
  result.mvpLoc = glGetUniformLocation(result.program, "uMvp")

  let vertices: array[30, float32] = [
    -0.5, 0.0, -0.5, 1.0, 0.2, 0.2,
     0.5, 0.0, -0.5, 0.2, 1.0, 0.2,
     0.5, 0.0, 0.5, 0.2, 0.2, 1.0,
    -0.5, 0.0, 0.5, 1.0, 1.0, 0.2,
     0.0, 0.8, 0.0, 1.0, 0.2, 1.0,
  ]

  let indices: array[18, uint16] = [
    0'u16, 1'u16, 4'u16,
    1'u16, 2'u16, 4'u16,
    2'u16, 3'u16, 4'u16,
    3'u16, 0'u16, 4'u16,
    0'u16, 1'u16, 2'u16,
    2'u16, 3'u16, 0'u16,
  ]

  result.indexCount = indices.len.GLsizei

  glGenVertexArrays(1, result.vao.addr)
  glGenBuffers(1, result.vbo.addr)
  glGenBuffers(1, result.ebo.addr)

  glBindVertexArray(result.vao)

  glBindBuffer(GL_ARRAY_BUFFER, result.vbo)
  glBufferData(
    GL_ARRAY_BUFFER,
    sizeof(vertices),
    vertices[0].addr,
    GL_STATIC_DRAW
  )

  glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, result.ebo)
  glBufferData(
    GL_ELEMENT_ARRAY_BUFFER,
    sizeof(indices),
    indices[0].addr,
    GL_STATIC_DRAW
  )

  let stride = (6 * sizeof(float32)).GLsizei
  glVertexAttribPointer(0, 3, cGL_FLOAT, GL_FALSE, stride, cast[pointer](0))
  glEnableVertexAttribArray(0)

  glVertexAttribPointer(
    1,
    3,
    cGL_FLOAT,
    GL_FALSE,
    stride,
    cast[pointer](3 * sizeof(float32))
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

proc drawPyramid(pyramid: PyramidGl, frameSize: Vec2, t: float32) =
  glViewport(0, 0, frameSize.x.GLint, frameSize.y.GLint)
  let aspect =
    if frameSize.y > 0: frameSize.x / frameSize.y else: 1.0'f32
  let proj = perspective(45.0'f32, aspect, 0.1'f32, 100.0'f32)

  let eye = vec3(1.6'f32, 1.1'f32, 2.2'f32)
  let center = vec3(0.0'f32, 0.25'f32, 0.0'f32)
  let angles = toAngles(eye, center)
  let view = translate(vec3(-eye.x, -eye.y, -eye.z)) * fromAngles(angles)
  let model = rotateY(t * 0.9'f32) * rotateX(-0.4'f32)
  var mvp = model * view * proj

  glUseProgram(pyramid.program)
  glUniformMatrix4fv(
    pyramid.mvpLoc,
    1,
    GL_FALSE,
    cast[ptr GLfloat](mvp.addr)
  )
  glBindVertexArray(pyramid.vao)
  glDrawElements(GL_TRIANGLES, pyramid.indexCount, GL_UNSIGNED_SHORT, nil)
  glBindVertexArray(0)
  glUseProgram(0)

proc makeOverlay(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(0, 0, 0, 0).color,
  ))

  let pad = 24'f32
  let panelW = min(320'f32, w * 0.4'f32)
  let panelRect = rect(w - panelW - pad, pad, panelW, h - pad * 2)
  let panelShadow = RenderShadow(
    style: DropShadow,
    blur: 18,
    spread: 0,
    x: 0,
    y: 10,
    color: rgba(0, 0, 0, 60).color,
  )

  let panelIdx = list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: panelRect,
    fill: rgba(20, 22, 32, 220).color,
    stroke: RenderStroke(weight: 1.5, color: rgba(255, 255, 255, 40).color),
    corners: [12.0'f32, 12.0, 12.0, 12.0],
    shadows: [panelShadow, RenderShadow(), RenderShadow(), RenderShadow()],
  ))

  let buttonPad = 18'f32
  let buttonW = panelRect.w - buttonPad * 2
  var buttonY = panelRect.y + buttonPad

  for i in 0 .. 3:
    let btnRect = rect(panelRect.x + buttonPad, buttonY, buttonW, 34'f32)
    discard list.addChild(panelIdx, Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: btnRect,
      fill: rgba(uint8(40 + i * 8), 90'u8, 160'u8, 200'u8).color,
      corners: [8.0'f32, 8.0, 8.0, 8.0],
    ))
    buttonY += 46'f32

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "opengl 3d overlay render":
  test "renderAndSwap + screenshot":
    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_3d_overlay.png"
    if fileExists(outPath):
      removeFile(outPath)
    block renderOnce:
      var img: Image
      var pyramid: PyramidGl
      var pyramidReady = false
      try:
        img = renderAndScreenshotOverlayOnce(
          drawBackground = proc(frameSize: Vec2) =
          if not pyramidReady:
            pyramid = initPyramid()
            pyramidReady = true
          useDepthBuffer(true)
          glClearColor(0.08, 0.1, 0.14, 1.0)
          glClear(GL_COLOR_BUFFER_BIT or GL_DEPTH_BUFFER_BIT)
          drawPyramid(pyramid, frameSize, 0.4'f32)
          useDepthBuffer(false),
          makeRenders = makeOverlay,
          outputPath = outPath,
          title = "figdraw test: 3d overlay",
        )
      except WindyError:
        skip()
        break renderOnce
      finally:
        if pyramidReady:
          destroyPyramid(pyramid)

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let expectedPath = "tests" / "expected" / "render_3d_overlay.png"
      if not fileExists(expectedPath):
        skip()
        break renderOnce
      let expected = pixie.readImage(expectedPath)
      let (diffScore, diffImg) = expected.diff(img)
      echo "Got image difference of: ", diffScore
      let diffThreshold = 100.0'f32
      if diffScore > diffThreshold:
        diffImg.writeFile(joinPath(outDir, "render_3d_overlay.diff.png"))
      check diffScore <= diffThreshold
