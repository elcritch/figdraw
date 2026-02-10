import std/[os, strutils]
import vmath

import ../commons
import ../figrender

const UseSiwinOpenGL = not (UseMetalBackend or UseVulkanBackend)
const NeedSiwinOpenGLContext = UseSiwinOpenGL or UseOpenGlFallback

when defined(macosx):
  import std/importutils
  import siwin/platforms/any/window as siAnyWindow
  import siwin/platforms/cocoa/window as siCocoaWindow
  import siwin/platforms/cocoa/cocoa as siCocoa
  when UseMetalBackend:
    import ./siwinmetal as siwinmetal
else:
  {.error: "siwinshim: unsupported OS".}

when NeedSiwinOpenGLContext:
  import figdraw/utils/glutils

export siAnyWindow, siCocoaWindow, vmath

privateAccess(WindowCocoaObj)

proc siwinBackendName*(): string =
  backendName(PreferredBackendKind)

proc siwinBackendName*[BackendState](renderer: FigRenderer[BackendState]): string =
  renderer.backendName()

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: " & siwinBackendName() & " + " & suffix

proc newSiwinWindow*(
    size: IVec2, fullscreen = false, title = "FigDraw", vsync = true, msaa = 0'i32
): Window =
  let window =
    newOpenglWindowCocoa(size = size, title = title, vsync = vsync, msaa = msaa)
  when NeedSiwinOpenGLContext:
    startOpenGL(openglVersion)
    window.makeCurrent()
  if fullscreen:
    window.fullscreen = true
  result = window

proc backingSize*(window: Window): IVec2 =
  let cocoaWindow = WindowCocoa(window)
  let contentView = cocoaWindow.handle.contentView
  let frame = contentView.frame
  let backing = contentView.convertRectToBacking(frame)
  ivec2(backing.size.width.int32, backing.size.height.int32)

proc logicalSize*(window: Window): Vec2 =
  vec2(window.backingSize()).descaled()

proc contentScale*(window: Window): float32 =
  let cocoaWindow = WindowCocoa(window)
  let contentView = cocoaWindow.handle.contentView
  let frame = contentView.frame
  if frame.size.width <= 0:
    return 1.0
  let backing = contentView.convertRectToBacking(frame)
  (backing.size.width / frame.size.width).float32

proc configureUiScale*(window: Window, envVar = "HDI"): bool =
  ## Returns true when scale should track contentScale (auto mode).
  let hdiEnv = getEnv(envVar)
  result = hdiEnv.len == 0
  if result:
    setFigUiScale window.contentScale()
  else:
    setFigUiScale hdiEnv.parseFloat()

proc refreshUiScale*(window: Window, autoScale: bool) =
  if autoScale:
    setFigUiScale window.contentScale()

proc presentNow*(window: Window) =
  if window of WindowCocoaOpengl:
    let cocoaWindow = WindowCocoa(window)
    cocoaWindow.handle.contentView.NSOpenGLView.openGLContext.flushBuffer()

when UseMetalBackend:
  type MetalLayerHandle* = siwinmetal.SiwinMetalLayerHandle

  proc attachMetalLayer*(
      window: Window,
      device: siwinmetal.MTLDevice,
      pixelFormat: siwinmetal.MTLPixelFormat = siwinmetal.MTLPixelFormatBGRA8Unorm,
  ): MetalLayerHandle =
    ## Attaches a CAMetalLayer to a siwin macOS window.
    let sz = window.backingSize()
    result = siwinmetal.attachMetalLayerToWindowPtr(
      cast[pointer](WindowCocoa(window).handle.int), sz.x, sz.y, device, pixelFormat
    )

  proc updateMetalLayer*(handle: MetalLayerHandle, window: Window) =
    ## Updates layer frame + drawable size (call on resize/redraw).
    let sz = window.backingSize()
    siwinmetal.updateMetalLayer(handle, sz.x, sz.y)

  proc setOpaque*(handle: MetalLayerHandle, opaque: bool) =
    ## Controls CAMetalLayer opacity without exposing Objective-C details.
    siwinmetal.setOpaque(handle, opaque)

type SiwinRenderBackend* = object
  ## Opaque per-window backend state used by siwin + FigDraw integration.
  window*: Window
  when UseMetalBackend:
    metalLayer*: MetalLayerHandle

proc setupBackend*(renderer: FigRenderer, window: Window) =
  ## One-time backend hookup between a siwin window and FigDraw renderer.
  renderer.backendState.window = window
  when UseMetalBackend:
    if renderer.backendKind() == rbMetal:
      try:
        renderer.backendState.metalLayer =
          attachMetalLayer(window, renderer.ctx.metalDevice())
        renderer.ctx.setPresentLayer(renderer.backendState.metalLayer.layer)
      except CatchableError as exc:
        when UseOpenGlFallback:
          renderer.useOpenGlFallback(exc.msg)
        else:
          raise exc

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## Per-frame pre-render backend maintenance.
  when UseMetalBackend:
    if renderer.backendKind() == rbMetal:
      let window = renderer.backendState.window
      renderer.backendState.metalLayer.updateMetalLayer(window)
  when NeedSiwinOpenGLContext:
    if renderer.backendKind() == rbOpenGL:
      renderer.backendState.window.makeCurrent()

proc endFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## Present a frame for backends that need explicit window buffer swap.
  if renderer.backendKind() == rbOpenGL:
    renderer.backendState.window.presentNow()
