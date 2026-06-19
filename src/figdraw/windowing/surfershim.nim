import pkg/surfer/app
import ../commons
import ../figrender

when UseVulkanBackend:
  import ../vulkan/vulkan_context

type SurferRenderBackend* = object
  # Surfer really doesn't need to juggle around a massive amount of state. :^)
  app*: App

proc setupBackend*(renderer: FigRenderer, app: App) =
  if renderer.backendKind() != rbVulkan:
    raise newException(Defect, "Surfer shim exclusively supports the Vulkan backend.")

  renderer.backendState.app = app

  let vkCtx = renderer.ctx.VulkanContext

  let surfacePtr = cast[pointer](app.vkSurface)
  if surfacePtr.isNil:
    raise newException(ValueError, "Surfer failed to provide a valid Vulkan surface.")

  vkCtx.setExternalSurface(surfacePtr, presentTargetWayland, ownedByContext = true)

proc beginFrame*(renderer: FigRenderer[SurferRenderBackend]) =
  discard

proc endFrame*(renderer: FigRenderer[SurferRenderBackend]) =
  if not renderer.backendState.app.isNil:
    renderer.backendState.app.queueRedraw()
