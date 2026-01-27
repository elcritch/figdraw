when not defined(js) and not defined(nimsuggest):
  {.fatal: "This example requires the Nim JS backend (nim js).".}

import std/[dom, jsconsole, jsffi]
import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/opengl/glapi
import figdraw/utils/glutils
import figdraw/webgl/api as webgl

import renderlist_100_common

var globalFrame = 0

proc main() =
  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  let canvas = webgl.asCanvas(document.createElement("canvas"))
  document.body.appendChild(canvas)

  document.body.style.margin = "0"
  document.body.style.overflow = "hidden"
  document.body.style.background = "#0c0f16"
  canvas.style.display = "block"

  let gl = cast[glapi.WebGL2RenderingContext](canvas.getContext("webgl2"))
  if gl.isNull or gl.isUndefined:
    console.error("WebGL2 not available")
    return

  setWebGLContext(gl)
  startOpenGL(openglVersion)

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = when not defined(useFigDrawTextures): 1024 else: 2048,
    pixelScale = app.pixelScale,
  )

  proc updateCanvas(): Vec2 =
    let dpr = if window.devicePixelRatio <= 0: 1.0 else: window.devicePixelRatio
    let cssWidth = max(window.innerWidth, 1)
    let cssHeight = max(window.innerHeight, 1)

    app.pixelScale = dpr.float32
    renderer.ctx.pixelScale = app.pixelScale

    let pixelWidth = int(cssWidth.float * dpr)
    let pixelHeight = int(cssHeight.float * dpr)
    if canvas.width != pixelWidth:
      canvas.width = pixelWidth
    if canvas.height != pixelHeight:
      canvas.height = pixelHeight
    canvas.style.width = cstring($cssWidth & "px")
    canvas.style.height = cstring($cssHeight & "px")

    result = vec2(cssWidth.float32, cssHeight.float32)

  proc drawFrame(time: float) =
    inc globalFrame
    let cssSize = updateCanvas()
    var renders = makeRenderTree(cssSize.x, cssSize.y, globalFrame)
    renderer.renderFrame(
      renders,
      vec2(canvas.width.float32, canvas.height.float32),
    )
    discard window.requestAnimationFrame(drawFrame)

  discard window.requestAnimationFrame(drawFrame)

when isMainModule:
  main()
