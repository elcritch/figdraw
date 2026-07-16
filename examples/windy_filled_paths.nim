import std/[math, strutils]
when not defined(emscripten):
  import std/os

when defined(useWindex):
  import windex
else:
  import figdraw/windowing/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as renderer

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc filledPath(area: Rect): Fig =
  let
    width = area.w
    height = area.h
    outer = initDrawableContour(
      [
        drawablePathLine(
          width * 0.12'f32, height * 0.30'f32, width * 0.12'f32, height * 0.70'f32
        ),
        drawablePathBezier(
          vec2(width * 0.12'f32, height * 0.70'f32),
          vec2(width * 0.50'f32, height * 1.12'f32),
          vec2(width * 0.88'f32, height * 0.70'f32),
        ),
        drawablePathLine(
          width * 0.88'f32, height * 0.70'f32, width * 0.88'f32, height * 0.30'f32
        ),
        drawablePathBezier(
          vec2(width * 0.88'f32, height * 0.30'f32),
          vec2(width * 0.50'f32, height * -0.12'f32),
          vec2(width * 0.12'f32, height * 0.30'f32),
        ),
      ]
    )
    hole = initDrawableContour(
      [
        drawablePathArc(
          center = vec2(width * 0.50'f32, height * 0.50'f32),
          radius = min(width, height) * 0.15'f32,
          startAngle = 0.0'f32,
          sweepAngle = PI.float32 * 2.0'f32,
        )
      ]
    )

  Fig(
    kind: nkDrawable,
    screenBox: area,
    fill: linear(
      rgba(37, 99, 235, 255),
      rgba(139, 92, 246, 255),
      rgba(236, 72, 153, 255),
      axis = fgaDiagTLBR,
    ),
    drawOps: @[drawablePath([outer, hole], dfrEvenOdd)],
  )

proc makeRenderTree*(width, height: float32): Renders =
  result = newRenders()

  let
    z = 0.ZLevel
    root = result.addRoot(
      z,
      Fig(
        kind: nkRectangle,
        screenBox: rect(0, 0, width, height),
        fill: rgba(245, 247, 252, 255),
      ),
    )
    margin = max(32.0'f32, min(width, height) * 0.10'f32)
    pathArea = rect(
      margin,
      margin,
      max(1.0'f32, width - margin * 2.0'f32),
      max(1.0'f32, height - margin * 2.0'f32),
    )

  discard result.addChild(z, root, filledPath(pathArea))

when isMainModule:
  var appRunning = true

  let
    initialSize = ivec2(900, 560)
    window = newWindyWindow(
      size = initialSize,
      fullscreen = false,
      title = windyWindowTitle("Filled Drawable Paths"),
    )

  when not defined(emscripten):
    if getEnv("HDI") != "":
      setFigUiScale getEnv("HDI").parseFloat()
    else:
      setFigUiScale window.contentScale()
  else:
    setFigUiScale window.contentScale()

  if initialSize != initialSize.scaled():
    window.size = initialSize.scaled()

  let drawRenderer =
    renderer.newFigRenderer(atlasSize = 256, backendState = WindyRenderBackend())
  drawRenderer.setupBackend(window)

  var
    renders = makeRenderTree(0.0'f32, 0.0'f32)
    lastSize = vec2(0.0'f32, 0.0'f32)

  proc redraw() =
    drawRenderer.beginFrame()
    let size = window.logicalSize()
    if size != lastSize:
      lastSize = size
      renders = makeRenderTree(size.x, size.y)
    drawRenderer.renderFrame(renders, size)
    drawRenderer.endFrame()

  window.onCloseRequest = proc() =
    appRunning = false
  window.onResize = proc() =
    redraw()

  try:
    var frames = 0
    while appRunning:
      pollEvents()
      redraw()
      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
