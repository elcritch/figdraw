import std/os
import pkg/pixie

import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

when not UseMetalBackend:
  import pkg/opengl
  import figdraw/utils/glutils

proc ensureTestOutputDir*(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

when not UseMetalBackend:
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

  var frame = AppFrame(windowTitle: title)
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, windowW.float32, windowH.float32),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  when UseMetalBackend:
    try:
      let renderer =
        glrenderer.newFigRenderer(atlasSize = atlasSize, pixelScale = app.pixelScale)

      var renders = makeRenders(windowW.float32.scaled(), windowH.float32.scaled())
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32).scaled())

      result = glrenderer.takeScreenshot()
      result.writeFile(outputPath)
    except ValueError:
      raise newException(WindyError, "Metal device not available")
  else:
    let window = newTestWindow(frame)
    if glGetString(GL_VERSION) == nil:
      raise newException(WindyError, "OpenGL context unavailable")

    let renderer =
      glrenderer.newFigRenderer(atlasSize = atlasSize, pixelScale = app.pixelScale)

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

proc renderAndScreenshotOverlayOnce*(
    drawBackground: proc(frameSize: Vec2) {.closure.},
    makeRenders: proc(w, h: float32): Renders {.closure.},
    outputPath: string,
    windowW = 800,
    windowH = 600,
    atlasSize = 2048,
    title = "figdraw test: opengl overlay screenshot",
): Image =
  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  var frame = AppFrame(windowTitle: title)
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, windowW.float32, windowH.float32),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  when UseMetalBackend:
    try:
      let renderer =
        glrenderer.newFigRenderer(atlasSize = atlasSize, pixelScale = app.pixelScale)
      let frameSize = vec2(windowW.float32, windowH.float32).scaled()
      var renders = makeRenders(windowW.float32.scaled(), windowH.float32.scaled())
      drawBackground(frameSize)
      renderer.renderOverlayFrame(renders, frameSize)

      result = glrenderer.takeScreenshot()
      result.writeFile(outputPath)
    except ValueError:
      raise newException(WindyError, "Metal device not available")
  else:
    let window = newTestWindow(frame)
    if glGetString(GL_VERSION) == nil:
      raise newException(WindyError, "OpenGL context unavailable")

    let renderer =
      glrenderer.newFigRenderer(atlasSize = atlasSize, pixelScale = app.pixelScale)

    try:
      pollEvents()
      let winInfo = window.getWindowInfo()
      let frameSize = winInfo.box.wh.scaled()
      var renders = makeRenders(winInfo.box.w.scaled(), winInfo.box.h.scaled())
      drawBackground(frameSize)
      renderer.renderOverlayFrame(renders, frameSize)
      window.swapBuffers()

      result = glrenderer.takeScreenshot(readFront = true)
      result.writeFile(outputPath)
    finally:
      window.close()
