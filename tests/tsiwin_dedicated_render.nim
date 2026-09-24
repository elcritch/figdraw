import std/unittest

import chroma
import figdraw/commons
import figdraw/fignodes
import figdraw/figrender
import figdraw/windowing/siwinshim

type FailingContext = ref object of BackendContext
  kindValue: RendererBackendKind
  finishedFrames: bool

var destroyedContexts: int

type DestructionProbe = object
  armed: bool

proc `=destroy`(probe: DestructionProbe) =
  if probe.armed:
    inc destroyedContexts

type CountedContext = ref object of BackendContext
  probe: DestructionProbe

proc installRendererCallback(window: Window) =
  let context = CountedContext(probe: DestructionProbe(armed: true))
  let renderer = newFigRenderer(context, SiwinRenderBackend(window: window))
  window.eventsHandler.onRender = proc(event: RenderEvent) =
    doAssert renderer.backendState.window == event.window

proc exerciseRendererCallback() =
  let window = Window()
  window.installRendererCallback()
  window.eventsHandler.onRender(RenderEvent(window: window))

method kind(ctx: FailingContext): RendererBackendKind =
  ctx.kindValue

method finishPendingFrames(ctx: FailingContext) =
  ctx.finishedFrames = true

method beginFrame(
    ctx: FailingContext, frameSize: Vec2, clearMain: bool, clearMainColor: Color
) =
  discard ctx
  discard frameSize
  discard clearMain
  discard clearMainColor
  raise newException(ValueError, "preferred backend failed")

suite "siwin dedicated rendering":
  test "finishing submitted frames delegates to the active backend":
    let context = FailingContext()
    let renderer = newFigRenderer(context, SiwinRenderBackend())
    renderer.finishPendingFrames()
    check context.finishedFrames

  test "releasing a window releases the renderer captured by its callback":
    destroyedContexts = 0
    exerciseRendererCallback()
    check destroyedContexts == 1

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
