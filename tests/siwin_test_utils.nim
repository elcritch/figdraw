import std/os
import pkg/pixie

import figdraw/windowing/siwinshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

when UseVulkanBackend:
  import pkg/vulkan/wrapper

when not UseMetalBackend and not UseVulkanBackend:
  import pkg/opengl

proc ensureTestOutputDir*(subdir = "output"): string =
  result = getCurrentDir() / "tests" / subdir
  createDir(result)

proc renderAndScreenshotOnce*(
    makeRenders: proc(w, h: float32): Renders {.closure.},
    outputPath: string,
    windowW = 800,
    windowH = 600,
    atlasSize = 2048,
    title = "figdraw test: siwin screenshot",
): Image =
  when UseMetalBackend:
    try:
      let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)

      var renders = makeRenders(windowW.float32, windowH.float32)
      renderer.renderFrame(renders, vec2(windowW.float32, windowH.float32))

      result = glrenderer.takeScreenshot(renderer)
      result.writeFile(outputPath)
    except ValueError:
      raise newException(ValueError, "Metal device not available")
  elif UseVulkanBackend:
    let renderer = glrenderer.newFigRenderer(
      atlasSize = atlasSize, backendState = SiwinRenderBackend()
    )
    let window = newSiwinWindow(
      renderer,
      size = ivec2(windowW.int32, windowH.int32),
      fullscreen = false,
      title = title,
    )
    try:
      renderer.setupBackend(window)

      window.firstStep()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      if renderer.backendKind() == rbOpenGL:
        result = glrenderer.takeScreenshot(renderer, readFront = false)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeScreenshot(renderer)
      result.writeFile(outputPath)
    except VulkanError as exc:
      raise newException(ValueError, "Vulkan device not available: " & exc.msg)
    except ValueError:
      raise newException(ValueError, "Vulkan device not available")
    finally:
      when not defined(emscripten):
        window.close()
  else:
    let window = newSiwinWindow(
      size = ivec2(windowW.int32, windowH.int32), fullscreen = false, title = title
    )
    try:
      window.firstStep()
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      glFinish()
      result = glrenderer.takeScreenshot(renderer, readFront = false)
      renderer.endFrame()
      presentNow(window)
      result.writeFile(outputPath)
    finally:
      when not defined(emscripten):
        window.close()
