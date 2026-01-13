import std/os
import pkg/pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/openglWindex
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/baserenderer

proc ensureTestOutputDir*(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

proc renderAndScreenshotOnce*(
    makeRenders: proc(w, h: float32): Renders {.closure.},
    outputPath: string,
    windowW = 800,
    windowH = 600,
    atlasSize = 2048,
    title = "figdraw test: opengl screenshot",
): Image =
  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  var frame = AppFrame(
    windowTitle: title,
    windowStyle: FrameStyle.DecoratedResizable,
    configFile: getCurrentDir() / "tests" / "opengl_screenshot",
    saveWindowState: false,
  )
  frame.windowInfo = WindowInfo(
    box: initBox(0, 0, windowW, windowH),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  let window = newWindexWindow(frame.addr)
  let renderer = glrenderer.newOpenGLRenderer(window, frame.addr, atlasSize = atlasSize)
  window.configureWindowEvents(renderer)

  try:
    window.pollEvents()
    let winInfo = window.getWindowInfo()
    let renders = makeRenders(winInfo.box.w.scaled(), winInfo.box.h.scaled())
    renderer.setRenderState(renders, winInfo)
    renderer.renderAndSwap()

    result = glrenderer.takeScreenshot(readFront = true)
    result.writeFile(outputPath)
  finally:
    window.closeWindow()

