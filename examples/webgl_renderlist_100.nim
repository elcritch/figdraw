when not defined(js) and not defined(nimsuggest):
  {.fatal: "This example requires the Nim JS backend (nim js).".}

import std/[dom, jsconsole, jsffi, strutils]

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

  document.body.style.margin = "0"
  document.body.style.overflow = "hidden"
  document.body.style.background = "#0c0f16"
  document.body.style.height = "100%"

  let root = document.createElement("div")
  root.style.position = "relative"
  root.style.width = "100%"
  root.style.height = "100%"
  root.style.overflow = "hidden"
  document.body.appendChild(root)

  canvas.style.display = "block"
  canvas.style.position = "absolute"
  canvas.style.left = "0"
  canvas.style.top = "0"
  root.appendChild(canvas)

  let textLayer = document.createElement("div")
  textLayer.style.position = "absolute"
  textLayer.style.left = "0"
  textLayer.style.top = "0"
  textLayer.style.width = "100%"
  textLayer.style.height = "100%"
  textLayer.style.pointerEvents = "none"
  textLayer.style.zIndex = "2"
  root.appendChild(textLayer)

  let fpsNode = document.createElement("div")
  fpsNode.style.position = "absolute"
  fpsNode.style.left = "12px"
  fpsNode.style.top = "10px"
  fpsNode.style.padding = "4px 6px"
  fpsNode.style.borderRadius = "6px"
  fpsNode.style.color = "#cfe2ff"
  fpsNode.style.background = "rgba(12, 15, 22, 0.55)"
  fpsNode.style.fontFamily =
    "ui-monospace, SFMono-Regular, Menlo, Consolas, monospace"
  fpsNode.style.fontSize = "12px"
  fpsNode.style.letterSpacing = "0.3px"
  fpsNode.textContent = "FPS: --"
  textLayer.appendChild(fpsNode)

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

  var fpsLastTime = 0.0
  var fpsFrames = 0

  proc drawFrame(time: float) =
    inc globalFrame
    let cssSize = updateCanvas()
    var renders = makeRenderTree(cssSize.x, cssSize.y, globalFrame)
    renderer.renderFrame(
      renders,
      vec2(canvas.width.float32, canvas.height.float32),
    )
    inc fpsFrames
    if fpsLastTime == 0.0:
      fpsLastTime = time
    let elapsed = time - fpsLastTime
    if elapsed >= 500.0:
      let fps = fpsFrames.float * 1000.0 / elapsed
      fpsNode.textContent = cstring("FPS: " & formatFloat(fps, ffDecimal, 1))
      fpsFrames = 0
      fpsLastTime = time
    discard window.requestAnimationFrame(drawFrame)

  discard window.requestAnimationFrame(drawFrame)

when isMainModule:
  main()
