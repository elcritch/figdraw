import std/os
import pkg/pixie
import pkg/opengl

import windy

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

proc ensureTestOutputDir*(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

proc newTestWindow(frame: AppFrame): Window =
  let window = newWindow(
    frame.windowTitle,
    ivec2(frame.windowInfo.box.w.int32, frame.windowInfo.box.h.int32),
    visible = false,
  )
  startOpenGL(openglVersion)
  window.makeContextCurrent()
  window.visible = true
  result = window

proc getWindowInfo(window: Window): WindowInfo =
  app.requestedFrame.inc

  result.minimized = window.minimized()
  result.pixelRatio = window.contentScale()

  let size = window.size()

  result.box.w = size.x.float32.descaled()
  result.box.h = size.y.float32.descaled()

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

  let window = newTestWindow(frame)
  if glGetString(GL_VERSION) == nil:
    raise newException(WindyError, "OpenGL context unavailable")

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = atlasSize,
    pixelScale = app.pixelScale,
  )

  try:
    pollEvents()
    let winInfo = window.getWindowInfo()
    var renders = makeRenders(winInfo.box.w.scaled(), winInfo.box.h.scaled())
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    window.swapBuffers()

    result = glrenderer.takeScreenshot(readFront = true)
    result.writeFile(outputPath)
  finally:
    window.close()
