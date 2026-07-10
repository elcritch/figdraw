import std/os
import pkg/pixie

import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

when UseVulkanBackend:
  import pkg/vulkan/wrapper

when not UseMetalBackend and not UseVulkanBackend:
  import pkg/opengl
  import figdraw/utils/glutils

proc ensureTestOutputDir*(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

when not UseMetalBackend and not UseVulkanBackend:
  proc newTestWindow(windowW, windowH: float32, title: string): Window =
    let window = newWindow(title, ivec2(windowW.int32, windowH.int32), visible = false)
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
      let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)

      var renders = makeRenders(windowW.float32, windowH.float32)
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32))

      result = glrenderer.takeScreenshot(renderer)
      result.writeFile(outputPath)
    except ValueError:
      raise newException(WindyError, "Metal device not available")
  elif UseVulkanBackend:
    let window = newWindyWindow(
      size = ivec2(windowW.int32, windowH.int32), fullscreen = false, title = title
    )
    try:
      when defined(windows):
        window.visible = true
        window.size = ivec2(windowW.int32, windowH.int32)
        var windowReady = false
        for _ in 0 ..< 50:
          pollEvents()
          let clientSize = window.backingSize()
          if clientSize.x > 0 and clientSize.y > 0:
            windowReady = true
            break
          sleep(10)
        if not windowReady:
          raise newException(WindyError, "Win32 window has no drawable client area")

      let renderer = glrenderer.newFigRenderer(
        atlasSize = atlasSize, backendState = WindyRenderBackend()
      )
      renderer.setupBackend(window)

      pollEvents()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      if renderer.backendKind() == rbOpenGL:
        # OpenGL fallback renders into the back buffer; capture before swap.
        result = glrenderer.takeOneFrameScreenshot(renderer)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeOneFrameScreenshot(renderer)
      result.writeFile(outputPath)
    except VulkanError as exc:
      raise newException(WindyError, "Vulkan device not available: " & exc.msg)
    except ValueError as exc:
      raise newException(WindyError, "Vulkan device not available: " & exc.msg)
    finally:
      window.close()
  else:
    let window = newTestWindow(windowW.float32, windowH.float32, title)
    if glGetString(GL_VERSION) == nil:
      raise newException(WindyError, "OpenGL context unavailable")

    let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)

    try:
      pollEvents()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.renderFrame(renders, sz)
      glFinish()
      result = glrenderer.takeOneFrameScreenshot(renderer)
      window.swapBuffers()
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
    raise newException(
      WindyError, "OpenGL overlay background rendering is unsupported on Metal backend"
    )
  elif UseVulkanBackend:
    raise newException(
      WindyError, "OpenGL overlay background rendering is unsupported on Vulkan backend"
    )
  else:
    let window = newTestWindow(windowW.float32, windowH.float32, title)
    if glGetString(GL_VERSION) == nil:
      raise newException(WindyError, "OpenGL context unavailable")

    let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)

    try:
      pollEvents()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x.scaled(), sz.y.scaled())
      drawBackground(sz)
      renderer.renderFrame(
        renders, vec2(windowW.float32, windowH.float32), clearMain = true
      )
      glFinish()
      result = glrenderer.takeOneFrameScreenshot(renderer)
      window.swapBuffers()
      result.writeFile(outputPath)
    finally:
      window.close()
