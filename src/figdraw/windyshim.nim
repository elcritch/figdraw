import unicode, vmath, windy/common

import ./commons
import ./figrender

const UseWindyOpenGL = not (UseMetalBackend or UseVulkanBackend)
const NeedWindyOpenGLContext = UseWindyOpenGL or UseOpenGlFallback

when defined(emscripten):
  import windy/platforms/emscripten/platform
elif defined(windows):
  import windy/platforms/win32/platform
elif defined(macosx):
  import std/importutils
  import darwin/app_kit/[nswindow, nsview]
  import darwin/objc/runtime
  import darwin/foundation/nsgeometry
  import windy/platforms/macos/platform
  when UseMetalBackend:
    import metalx/[cametal, metal, view]
elif defined(linux) or defined(bsd):
  import windy/platforms/linux/platform
else:
  {.error: "windyshim: unsupported OS".}

when NeedWindyOpenGLContext:
  import figdraw/utils/glutils

export common, platform, unicode, vmath

proc windyBackendName*(): string =
  backendName(PreferredBackendKind)

proc windyBackendName*[BackendState](renderer: FigRenderer[BackendState]): string =
  renderer.backendName()

proc windyWindowTitle*(suffix = "Windy RenderList"): string =
  "figdraw: " & windyBackendName() & " + " & suffix

proc logicalSize*(window: Window): Vec2 =
  result = vec2(window.size()).descaled()

proc newWindyWindow*(size: IVec2, fullscreen = false, title = "FigDraw"): Window =
  let size = scaled(
    when defined(emscripten):
      ivec2(0, 0)
    else:
      size
  )
  let window = newWindow(title, size, visible = false)

  when NeedWindyOpenGLContext:
    startOpenGL(openglVersion)

  when not defined(emscripten):
    if fullscreen:
      window.fullscreen = true
    else:
      window.size = size
    window.visible = true
  when NeedWindyOpenGLContext:
    window.makeContextCurrent()

  return window

when defined(macosx) and not compiles(cocoaWindow(Window())):
  privateAccess(Window)
  proc cocoaWindow*(window: Window): NSWindow =
    cast[NSWindow](cast[pointer](window.inner.int))

  proc cocoaContentView*(window: Window): NSView =
    cocoaWindow(window).contentView()

when UseMetalBackend:
  type MetalLayerHandle* = object
    ## Small helper container so callers don't need to depend on metalx/view.
    hostView*: NSView
    layer*: CAMetalLayer

  proc attachMetalLayer*(
      window: Window,
      device: MTLDevice,
      pixelFormat: MTLPixelFormat = MTLPixelFormatBGRA8Unorm,
  ): MetalLayerHandle =
    ## Attaches a CAMetalLayer to a Windy macOS window.
    ##
    ## Windowing code still owns the window; FigDraw only wires a host view + layer.
    result.hostView = attachMetalHostView(cocoaWindow(window))
    result.layer = CAMetalLayer.alloc().init()
    result.layer.setDevice(device)
    result.layer.setPixelFormat(pixelFormat)
    result.hostView.setLayer(result.layer)
    # Initial sizing.
    result.layer.setFrame(result.hostView.bounds())
    let sz = window.size()
    result.layer.setDrawableSize(NSSize(width: sz.x.float, height: sz.y.float))

  proc updateMetalLayer*(handle: MetalLayerHandle, window: Window) =
    ## Updates layer frame + drawable size (call on resize/redraw).
    handle.layer.setFrame(handle.hostView.bounds())
    let sz = window.size()
    handle.layer.setDrawableSize(NSSize(width: sz.x.float, height: sz.y.float))

when UseVulkanBackend and (defined(linux) or defined(bsd)):
  import chronicles
  import std/importutils
  import x11/xlib

  import vulkan/vulkan_context

  privateAccess(Window)

  var vulkanDisplay: PDisplay

  proc sharedVulkanDisplay(): PDisplay =
    if vulkanDisplay.isNil:
      vulkanDisplay = XOpenDisplay(nil)
    result = vulkanDisplay

  proc attachVulkanSurface*(window: Window, ctx: VulkanContext) =
    var display = sharedVulkanDisplay()
    if display.isNil:
      raise newException(ValueError, "Failed to open X11 display for Vulkan surface")
    info "attachVulkanSurface xlib",
      display = cast[uint64](display), window = cast[uint64](window.handle)
    ctx.setPresentXlibTarget(cast[pointer](display), cast[uint64](window.handle))

when UseVulkanBackend and defined(windows):
  import std/importutils
  import windy/platforms/win32/windefs

  privateAccess(Window)

  proc attachVulkanSurface*(window: Window, ctx: Context) =
    let hinstance = cast[pointer](GetModuleHandleW(nil))
    let hwnd = cast[pointer](window.hWnd)
    ctx.setPresentWin32Target(hinstance, hwnd)

type WindyRenderBackend* = object
  ## Opaque per-window backend state used by windy + FigDraw integration.
  window*: Window
  when UseMetalBackend:
    metalLayer*: MetalLayerHandle

proc setupBackend*(renderer: FigRenderer, window: Window) =
  ## One-time backend hookup between a Windy window and FigDraw renderer.
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
  elif UseVulkanBackend:
    if renderer.backendKind() == rbVulkan:
      try:
        attachVulkanSurface(window, renderer.ctx)
      except CatchableError as exc:
        when UseOpenGlFallback:
          renderer.useOpenGlFallback(exc.msg)
        else:
          raise exc

proc beginFrame*(renderer: FigRenderer[WindyRenderBackend]) =
  ## Per-frame pre-render backend maintenance.
  when UseMetalBackend:
    if renderer.backendKind() == rbMetal:
      let window = renderer.backendState.window
      renderer.backendState.metalLayer.updateMetalLayer(window)
  when NeedWindyOpenGLContext:
    if renderer.backendKind() == rbOpenGL:
      renderer.backendState.window.makeContextCurrent()

proc endFrame*(renderer: FigRenderer[WindyRenderBackend]) =
  ## Present a frame for backends that need explicit window buffer swap.
  if renderer.backendKind() == rbOpenGL:
    renderer.backendState.window.swapBuffers()
