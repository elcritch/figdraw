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
        result = glrenderer.takeOneFrameScreenshot(renderer)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeOneFrameScreenshot(renderer)
      if result.isNil or result.width <= 0 or result.height <= 0 or result.data.len == 0:
        raise newException(
          ValueError, "Vulkan screenshot unavailable (no present target or empty frame)"
        )
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
      renderer.renderFrame(renders, sz)
      glFinish()
      result = glrenderer.takeOneFrameScreenshot(renderer)
      presentNow(window)
      result.writeFile(outputPath)
    finally:
      when not defined(emscripten):
        window.close()

proc renderAndScreenshotSequence*(
    makeInitialRenders: proc(w, h: float32): Renders {.closure.},
    makeUpdatedRenders: proc(w, h: float32): Renders {.closure.},
    initialPath: string,
    updatedPath: string,
    windowW = 800,
    windowH = 600,
    atlasSize = 2048,
    title = "figdraw test: siwin screenshot sequence",
): tuple[initial, updated: Image] =
  when UseMetalBackend:
    try:
      let renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)

      var initialRenders = makeInitialRenders(windowW.float32, windowH.float32)
      renderer.renderFrame(initialRenders, vec2(windowW.float32, windowH.float32))
      result.initial = glrenderer.takeScreenshot(renderer)
      result.initial.writeFile(initialPath)

      var updatedRenders = makeUpdatedRenders(windowW.float32, windowH.float32)
      renderer.renderFrame(updatedRenders, vec2(windowW.float32, windowH.float32))
      result.updated = glrenderer.takeScreenshot(renderer)
      result.updated.writeFile(updatedPath)
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

    proc capture(
        makeRenders: proc(w, h: float32): Renders {.closure.}, outputPath: string
    ): Image =
      let sz = window.logicalSize()
      var renders = makeRenders(sz.x, sz.y)
      renderer.beginFrame()
      renderer.renderFrame(renders, sz)
      if renderer.backendKind() == rbOpenGL:
        result = glrenderer.takeOneFrameScreenshot(renderer)
        renderer.endFrame()
      else:
        renderer.endFrame()
        result = glrenderer.takeOneFrameScreenshot(renderer)
      if result.isNil or result.width <= 0 or result.height <= 0 or result.data.len == 0:
        raise newException(
          ValueError, "Vulkan screenshot unavailable (no present target or empty frame)"
        )
      result.writeFile(outputPath)

    try:
      renderer.setupBackend(window)
      window.firstStep()
      result.initial = capture(makeInitialRenders, initialPath)
      result.updated = capture(makeUpdatedRenders, updatedPath)
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
      let
        sz = window.logicalSize()
        renderer = glrenderer.newFigRenderer(atlasSize = atlasSize)

      var initialRenders = makeInitialRenders(sz.x, sz.y)
      renderer.renderFrame(initialRenders, sz)
      glFinish()
      result.initial = glrenderer.takeOneFrameScreenshot(renderer)
      presentNow(window)
      result.initial.writeFile(initialPath)

      var updatedRenders = makeUpdatedRenders(sz.x, sz.y)
      renderer.renderFrame(updatedRenders, sz)
      glFinish()
      result.updated = glrenderer.takeOneFrameScreenshot(renderer)
      presentNow(window)
      result.updated.writeFile(updatedPath)
    finally:
      when not defined(emscripten):
        window.close()
