when defined(emscripten):
  import std/strutils
else:
  import std/[os, strutils]

import figdraw
import figdraw/windowing/windyshim

import renderfragments_common

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

when isMainModule:
  var appRunning = true
  let
    initialSize = ivec2(900, 620)
    title = windyWindowTitle("Windy RenderFragments")
    window = newWindyWindow(size = initialSize, fullscreen = false, title = title)

  when defined(emscripten):
    setFigUiScale(window.contentScale())
  else:
    if getEnv("HDI") != "":
      setFigUiScale(getEnv("HDI").parseFloat())
    else:
      setFigUiScale(window.contentScale())
  if initialSize != initialSize.scaled():
    window.size = initialSize.scaled()

  let renderer = newFigRenderer(atlasSize = 256, backendState = WindyRenderBackend())
  renderer.setupBackend(window)

  var
    frames = 0
    example = initFragmentExample(window.logicalSize())

  proc redraw() =
    let logicalSize = window.logicalSize()
    example.resize(logicalSize)
    example.update()

    renderer.beginFrame()
    renderer.renderFrame(example.renders, logicalSize)
    renderer.endFrame()

  window.onCloseRequest = proc() =
    appRunning = false
  window.onResize = proc() =
    redraw()

  try:
    while appRunning:
      pollEvents()
      redraw()
      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
  finally:
    when not defined(emscripten):
      window.close()
