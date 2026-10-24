## Direct siwin API: nim r examples/software_window.nim
## Direct Windy API: nim r -d:figdraw.softwareWindow=windy examples/software_window.nim
## Run atlas install --keepFeatures --feature=figdraw.uirelays first.
import std/os
import figdraw
import figdraw/software/windowing
import ./software_scene

const SoftwareWindow {.strdefine: "figdraw.softwareWindow".} = "siwin"

when SoftwareWindow == "windy":
  import figdraw/windowing/windyshim
elif SoftwareWindow == "siwin":
  import figdraw/windowing/siwinshim
else:
  {.error: "figdraw.softwareWindow must be siwin or windy".}

proc main() =
  var running = true
  when SoftwareWindow == "windy":
    let window = newWindyWindow(ivec2(560, 360), title = "FigDraw CPU + Windy")
    setFigUiScale(window.contentScale())
    let host = newFigRenderer(atlasSize = 1024, backendState = WindyRenderBackend())
  else:
    when UseVulkanBackend:
      let host = newFigRenderer(atlasSize = 1024, backendState = SiwinRenderBackend())
      let window = newSiwinWindow(host, ivec2(560, 360), title = "FigDraw CPU + siwin")
    else:
      let window = newSiwinWindow(ivec2(560, 360), title = "FigDraw CPU + siwin")
      let host = newFigRenderer(atlasSize = 1024, backendState = SiwinRenderBackend())
    let autoScale = window.configureUiScale()
  host.setupBackend(window)
  let cpu = newFigRenderer(
    newSoftwareContext(
      presenter = proc(image: Image) =
        host.presentSoftwareFrame(image)
    )
  )

  var scene: SoftwareSceneCache

  proc redraw() =
    host.beginFrame()
    let size = window.logicalSize()
    var nodes = scene.softwareScene(size.x, size.y)
    cpu.renderFrame(nodes, size)
    host.endFrame()

  let runOnce = getEnv("FIGDRAW_RUN_ONCE") == "1"
  when SoftwareWindow == "windy":
    window.onCloseRequest = proc() =
      running = false
    try:
      while running:
        pollEvents()
        if running:
          redraw()
          if runOnce:
            running = false
          os.sleep(16)
    finally:
      host.finishPendingFrames()
      window.close()
  else:
    window.eventsHandler = WindowEventsHandler(
      onClose: proc(event: CloseEvent) =
        running = false,
      onResize: proc(event: ResizeEvent) =
        window.refreshUiScale(autoScale)
        window.redraw(),
      onRender: proc(event: RenderEvent) =
        redraw(),
    )
    window.firstStep()
    try:
      while running and window.opened:
        window.redraw()
        window.step()
        if runOnce:
          running = false
        os.sleep(16)
    finally:
      host.finishPendingFrames()
      window.close()

main()
