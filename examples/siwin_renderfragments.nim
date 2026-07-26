import figdraw
import figdraw/windowing/siwinshim

import renderfragments_common

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

when isMainModule:
  var appRunning = true
  let
    initialSize = ivec2(900, 620)
    title = siwinWindowTitle("Siwin RenderFragments")

  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize = 256, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = initialSize, title = title, vsync = true)
  else:
    let appWindow = newSiwinWindow(size = initialSize, title = title, vsync = true)
    let renderer = newFigRenderer(atlasSize = 256, backendState = SiwinRenderBackend())

  let useAutoScale = appWindow.configureUiScale()
  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin RenderFragments")

  var
    frames = 0
    example = initFragmentExample(appWindow.logicalSize())

  proc redraw() =
    let logicalSize = appWindow.logicalSize()
    example.resize(logicalSize)
    example.update()

    renderer.beginFrame()
    renderer.renderFrame(example.renders, logicalSize)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      appRunning = false,
    onResize: proc(e: ResizeEvent) =
      appWindow.refreshUiScale(useAutoScale)
      appWindow.redraw(),
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
    while appRunning and appWindow.opened:
      appWindow.redraw()
      appWindow.step()
      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
  finally:
    when not defined(emscripten):
      appWindow.close()
