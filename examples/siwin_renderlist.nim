import std/times
import std/strutils
when not defined(emscripten):
  import std/os
import chroma
import chronicles

import figdraw/windowing/siwinshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

logScope:
  scope = "siwin_renderlist"

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
      shadows: [
        RenderShadow(
          style: InnerShadow,
          blur: 12,
          spread: 6,
          x: 0,
          y: 0,
          color: rgba(255, 255, 255, 255).color,
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

when isMainModule:
  var app_running = true

  let title = siwinWindowTitle("Siwin RenderList")
  let size = ivec2(800, 600)
  when UseVulkanBackend:
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
    let appWindow = newSiwinWindow(renderer, size = size, title = title, vsync = true)
  else:
    let appWindow = newSiwinWindow(size = size, title = title, vsync = true)
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()
  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin RenderList")

  info "Siwin renderlist startup",
    backend = renderer.backendName().toLowerAscii(),
    windowW = appWindow.backingSize().x,
    windowH = appWindow.backingSize().y,
    logicalW = appWindow.logicalSize().x,
    logicalH = appWindow.logicalSize().y,
    scale = appWindow.contentScale()

  var renders = makeRenderTree(0.0'f32, 0.0'f32)
  var lastSize = vec2(0.0'f32, 0.0'f32)
  var redrawCount = 0

  proc redraw() =
    inc redrawCount
    renderer.beginFrame()
    let sz = appWindow.logicalSize()
    if sz != lastSize:
      lastSize = sz
      renders = makeRenderTree(sz.x, sz.y)
    if redrawCount <= 3 or (redrawCount mod 240) == 0:
      debug "redraw start", redraw = redrawCount, width = sz.x, height = sz.y
    renderer.renderFrame(renders, sz)
    if redrawCount <= 3 or (redrawCount mod 240) == 0:
      debug "redraw end", redraw = redrawCount
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      info "Close requested"
      app_running = false,
    onResize: proc(e: ResizeEvent) =
      appWindow.refreshUiScale(useAutoScale)
      redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        close(e.window)
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  appWindow.firstStep()
  appWindow.refreshUiScale(useAutoScale)

  try:
    while app_running and appWindow.opened:
      appWindow.redraw()
      appWindow.step()

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
      appWindow.close()
