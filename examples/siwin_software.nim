## atlas install --keepFeatures --feature=figdraw.siwin --feature=figdraw.harfbuzz
## nim r examples/siwin_software.nim
## Pure software window: sdfy + automatic Sigils workers, Pixie composition.
import std/os
import pkg/siwin/window
import figdraw
import figdraw/software/siwin
import ./software_scene

proc main() =
  let window = newSoftwareRenderingWindow(
    size = ivec2(560, 360), title = "FigDraw software + siwin"
  )
  let renderer = newSiwinSoftwareRenderer(window)
  var scene: SoftwareSceneCache
  var running = true
  let runOnce = getEnv("FIGDRAW_RUN_ONCE") == "1"
  window.eventsHandler = WindowEventsHandler(
    onClose: proc(event: CloseEvent) =
      running = false,
    onResize: proc(event: ResizeEvent) =
      event.window.redraw(),
    onRender: proc(event: RenderEvent) =
      let size = configureSiwinSoftwareScale(event.window)
      if size.x > 0 and size.y > 0:
        var nodes = scene.softwareScene(size.x, size.y)
        renderer.renderFrame(nodes, size)
      if runOnce:
        running = false
    ,
  )
  try:
    window.firstStep()
    while running and window.opened:
      window.redraw()
      window.step()
      os.sleep(16)
  finally:
    # The presenter retains the window; release event closures before closing.
    window.eventsHandler = WindowEventsHandler()
    window.close()

main()
