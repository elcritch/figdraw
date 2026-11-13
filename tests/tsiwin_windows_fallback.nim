import std/unittest
import figdraw/commons

when defined(windows) and UseVulkanBackend and UseOpenGlFallback and
    (defined(figdrawTestVulkanInitFailure) or defined(vulkanCrashTest)):
  import figdraw/[figrender, fignodes]
  import figdraw/windowing/siwinshim

  suite "Windows Vulkan to OpenGL fallback":
    test "initializes and presents using a software window":
      let window = newSiwinWindow(size = ivec2(64, 64))
      defer:
        if window.opened:
          window.close()
      block:
        let renderer =
          newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
        renderer.setupBackend(window)
        check renderer.backendKind() == rbOpenGL
        window.firstStep()
        var nodes = newRenders()
        renderer.beginFrame()
        renderer.renderFrame(nodes, window.logicalSize())
        renderer.endFrame()
        renderer.finishPendingFrames()
