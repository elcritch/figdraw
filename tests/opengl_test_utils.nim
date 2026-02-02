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
  proc newTestWindow(windowW, windowH: float32, title: string): Window =
    let window = newWindow(
      title,
      ivec2(windowW.int32, windowH.int32),
      visible = false,
    )
    startOpenGL(openglVersion)
    window.makeContextCurrent()
    window.visible = true
    result = window

proc renderAndScreenshotOnce*(
    makeRenders: proc(w, h: float32): Renders {.closure.},
    outputPath: string,
    windowW = 800,
    windowH = 600,
    atlasSize = 2048,
    title = "figdraw test: opengl screenshot",
): Image =

  when UseMetalBackend:
    try:
      let renderer =
        glrenderer.newFigRenderer(atlasSize = atlasSize)

      var renders = makeRenders(windowW.float32.scaled(), windowH.float32.scaled())
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32).scaled())

      result = glrenderer.takeScreenshot(renderer)
      result.writeFile(outputPath)
    except ValueError:
      raise newException(WindyError, "Metal device not available")
  else:
    let window = newTestWindow(windowW.float32, windowH.float32, title)
    if glGetString(GL_VERSION) == nil:
      raise newException(WindyError, "OpenGL context unavailable")

    let renderer =
      glrenderer.newFigRenderer(atlasSize = atlasSize)

    try:
      pollEvents()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.renderFrame(renders, sz)
      window.swapBuffers()

      result = glrenderer.takeScreenshot(renderer, readFront = true)
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

  when UseMetalBackend:
    try:
      let renderer =
        glrenderer.newFigRenderer(atlasSize = atlasSize)
      let frameSize = vec2(windowW.float32, windowH.float32).scaled()
      var renders = makeRenders(windowW.float32.scaled(), windowH.float32.scaled())
      drawBackground(frameSize)
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32), clearMain = true)

      result = glrenderer.takeScreenshot(renderer)
      result.writeFile(outputPath)
    except ValueError:
      raise newException(WindyError, "Metal device not available")
  else:
    let window = newTestWindow(windowW.float32, windowH.float32, title)
    if glGetString(GL_VERSION) == nil:
      raise newException(WindyError, "OpenGL context unavailable")

    let renderer =
      glrenderer.newFigRenderer(atlasSize = atlasSize)

    try:
      pollEvents()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x.scaled(), sz.y.scaled())
      drawBackground(sz)
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32), clearMain = true)
      window.swapBuffers()

      result = glrenderer.takeScreenshot(renderer, readFront = true)
      result.writeFile(outputPath)
    finally:
      window.close()
