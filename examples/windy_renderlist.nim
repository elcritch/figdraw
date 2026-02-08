import std/times
import std/strutils
when not defined(emscripten):
  import std/os
import chroma
import chronicles

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

logScope:
  scope = "windy_renderlist"

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc makeRenderTree*(w, h: float32): Renders =
  result = Renders()

  let rootIdx = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 255).color,
    ),
  )

  discard result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      corners: [10.0'f32, 20.0, 30.0, 40.0],
      screenBox: rect(60, 60, 220, 140),
      fill: rgba(220, 40, 40, 255).color,
      stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 255).color),
    ),
  )
  discard result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(320, 120, 220, 140),
      fill: rgba(40, 180, 90, 255).color,
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 10,
          spread: 10,
          x: 10,
          y: 10,
          color: rgba(0, 0, 0, 55).color,
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )
  discard result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(180, 300, 220, 140),
      fill: rgba(60, 90, 220, 255).color,
    ),
  )

when isMainModule:
  var app_running = true

  let title = windyWindowTitle("Windy RenderList")
  let size = ivec2(800, 600)
  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  let window = newWindyWindow(size = size, fullscreen = false, title = title)

  if getEnv("HDI") != "":
    setFigUiScale getEnv("HDI").parseFloat()
  else:
    setFigUiScale window.contentScale()
  if size != size.scaled():
    window.size = size.scaled()

  let renderer =
    glrenderer.newFigRenderer(atlasSize = 192, backendState = WindyRenderBackend())
  renderer.setupBackend(window)

  info "Windy renderlist startup",
    backend = renderer.windyBackendName().toLowerAscii(),
    windowW = window.size().x,
    windowH = window.size().y,
    scale = window.contentScale()

  var renders = makeRenderTree(0.0'f32, 0.0'f32)
  var lastSize = vec2(0.0'f32, 0.0'f32)
  var redrawCount = 0

  proc redraw() =
    inc redrawCount
    renderer.beginFrame()
    let sz = window.logicalSize()
    if sz != lastSize:
      lastSize = sz
      renders = makeRenderTree(sz.x, sz.y)
      info "Logical size changed", width = sz.x, height = sz.y, redraw = redrawCount
    if redrawCount <= 3 or (redrawCount mod 240) == 0:
      debug "redraw start", redraw = redrawCount, width = sz.x, height = sz.y
    renderer.renderFrame(renders, sz)
    if redrawCount <= 3 or (redrawCount mod 240) == 0:
      debug "redraw end", redraw = redrawCount
    renderer.endFrame()

  window.onCloseRequest = proc() =
    info "Close requested"
    app_running = false
  window.onResize = proc() =
    let physical = window.size()
    let logical = window.logicalSize()
    info "Window resize callback",
      physicalW = physical.x,
      physicalH = physical.y,
      logicalW = logical.x,
      logicalH = logical.y
    redraw()

  try:
    while app_running:
      pollEvents()
      redraw()

      inc frames
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        info "Render loop heartbeat", fps = fps, frames = frames, redraws = redrawCount
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        app_running = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
