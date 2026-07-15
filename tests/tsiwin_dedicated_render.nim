import std/unittest

import figdraw
import figdraw/figrender
import figdraw/windowing/siwinshim

type FailingContext = ref object of BackendContext
  kindValue: RendererBackendKind

method kind(ctx: FailingContext): RendererBackendKind =
  ctx.kindValue

method beginFrame(
    ctx: FailingContext, frameSize: Vec2, clearMain: bool, clearMainColor: Color
) =
  discard ctx
  discard frameSize
  discard clearMain
  discard clearMainColor
  raise newException(ValueError, "preferred backend failed")

suite "siwin dedicated rendering":
  test "reports platform backend support":
    check not backendSupportsDedicatedRenderThread(rbOpenGL)
    when UseMetalBackend and defined(macosx):
      check backendSupportsDedicatedRenderThread(rbMetal)
    else:
      check not backendSupportsDedicatedRenderThread(rbMetal)
    when UseVulkanBackend:
      check backendSupportsDedicatedRenderThread(rbVulkan)
    else:
      check not backendSupportsDedicatedRenderThread(rbVulkan)

  test "requires a configured presentation target":
    let renderer = newFigRenderer(
      FailingContext(kindValue: PreferredBackendKind), SiwinRenderBackend()
    )
    check not renderer.supportsDedicatedRenderThread()
    expect ValueError:
      renderer.useDedicatedRenderThread()
    check not renderer.backendState.dedicatedRender

  test "dedicated rendering does not fall back to window-bound OpenGL":
    when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
      let
        context = FailingContext(kindValue: PreferredBackendKind)
        renderer = newFigRenderer(context, SiwinRenderBackend())
      var renders = newRenders()
      expect ValueError:
        figrender.renderFrame(
          renderer, renders, vec2(64, 64), allowOpenGlFallback = false
        )
      check renderer.ctx == context
    else:
      skip()
