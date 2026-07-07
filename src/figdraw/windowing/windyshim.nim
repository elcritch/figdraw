import unicode, vmath, windy/common

import ../commons
import ../figrender

const UseWindyOpenGL = not (UseMetalBackend or UseVulkanBackend)
const NeedWindyOpenGLContext = UseWindyOpenGL or UseOpenGlFallback

when defined(emscripten):
  import windy/platforms/emscripten/platform
elif defined(windows):
  import windy/platforms/win32/platform
elif defined(macosx):
  import std/importutils
  import std/math
  import darwin/app_kit/[nswindow, nsview]
  import darwin/objc/runtime
  import windy/platforms/macos/platform
  when UseMetalBackend or UseVulkanBackend:
    import darwin/core_graphics/cggeometry
    import darwin/foundation/nsgeometry
    import metalx/[cametal, metal, view]
elif defined(linux) or defined(bsd):
  import windy/platforms/linux/platform
else:
  {.error: "windyshim: unsupported OS".}

when UseVulkanBackend:
  import ../vulkan/vulkan_context

when NeedWindyOpenGLContext:
  import figdraw/utils/glutils

export common, platform, unicode, vmath

proc windyBackendName*(): string =
  backendName(PreferredBackendKind)

proc windyBackendName*[BackendState](renderer: FigRenderer[BackendState]): string =
  renderer.backendName()

proc windyWindowTitle*(suffix = "Windy RenderList"): string =
  "figdraw: " & windyBackendName() & " + " & suffix

when defined(macosx) and not compiles(cocoaWindow(Window())):
  privateAccess(Window)
  proc cocoaWindow*(window: Window): NSWindow =
    cast[NSWindow](cast[pointer](window.inner.int))

  proc cocoaContentView*(window: Window): NSView =
    cocoaWindow(window).contentView()

proc backingSize*(window: Window): IVec2 =
  when defined(macosx):
    let contentView = cocoaContentView(window)
    let backing = contentView.convertRectToBacking(contentView.bounds())
    ivec2(
      max(0'i32, ceil(backing.size.width).int32),
      max(0'i32, ceil(backing.size.height).int32),
    )
  else:
    window.size()

proc logicalSize*(window: Window): Vec2 =
  result = vec2(window.backingSize()).descaled()

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

when (UseMetalBackend or UseVulkanBackend) and defined(macosx):
  type MetalLayerHandle* = object
    ## Small helper container so callers don't need to depend on metalx/view.
    hostView*: NSView
    layer*: CAMetalLayer

  type CATransaction = ptr object of NSObject

  proc begin(t: typedesc[CATransaction]) {.objc: "begin".}
  proc commit(t: typedesc[CATransaction]) {.objc: "commit".}
  proc setDisableActions(
    t: typedesc[CATransaction], disabled: bool
  ) {.objc: "setDisableActions:".}

  proc setFrame(view: NSView, rect: NSRect) {.objc: "setFrame:".}
  proc setOpaque(layer: CAMetalLayer, opaque: bool) {.objc: "setOpaque:".}
  proc setPresentsWithTransaction(
    layer: CAMetalLayer, enabled: bool
  ) {.objc: "setPresentsWithTransaction:".}

  proc setContentsScale(
    layer: CAMetalLayer, scale: CGFloat
  ) {.objc: "setContentsScale:".}

  template withoutLayerActions(body: untyped) =
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    body
    CATransaction.commit()

  proc safeDrawableDimension(v: int32): CGFloat =
    ## CAMetalLayer rejects zero-sized drawables during transient resize states.
    max(1'i32, v).CGFloat

  proc backingScale(bounds: NSRect, backingWidth, backingHeight: int32): CGFloat =
    if bounds.size.width > 0:
      return safeDrawableDimension(backingWidth) / bounds.size.width
    if bounds.size.height > 0:
      return safeDrawableDimension(backingHeight) / bounds.size.height
    1.0

  proc syncMetalLayer(handle: MetalLayerHandle, window: Window) =
    let contentBounds = cocoaContentView(window).bounds()
    let sz = window.backingSize()

    withoutLayerActions:
      handle.hostView.setFrame(contentBounds)

      let bounds = handle.hostView.bounds()
      handle.layer.setFrame(bounds)
      handle.layer.setContentsScale(backingScale(bounds, sz.x, sz.y))
      handle.layer.setDrawableSize(
        NSSize(width: safeDrawableDimension(sz.x), height: safeDrawableDimension(sz.y))
      )

  proc attachMetalLayer*(
      window: Window,
      device: MTLDevice,
      pixelFormat: MTLPixelFormat = MTLPixelFormatBGRA8Unorm,
      presentsWithTransaction = false,
  ): MetalLayerHandle =
    ## Attaches a CAMetalLayer to a Windy macOS window.
    ##
    ## Windowing code still owns the window; FigDraw only wires a host view + layer.
    result.hostView = attachMetalHostView(cocoaWindow(window))
    result.layer = CAMetalLayer.alloc().init()
    result.layer.setDevice(device)
    result.layer.setPixelFormat(pixelFormat)
    result.layer.setOpaque(true)
    result.layer.setPresentsWithTransaction(presentsWithTransaction)
    result.hostView.setLayer(result.layer)
    result.syncMetalLayer(window)

  proc updateMetalLayer*(handle: MetalLayerHandle, window: Window) =
    ## Updates layer frame + drawable size (call on resize/redraw).
    handle.syncMetalLayer(window)

  proc setOpaque*(handle: MetalLayerHandle, opaque: bool) =
    ## Controls CAMetalLayer opacity without exposing Objective-C details.
    handle.layer.setOpaque(opaque)

when UseVulkanBackend and (defined(linux) or defined(bsd)):
  import chronicles
  import std/importutils
  import x11/xlib

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

  proc attachVulkanSurface*(window: Window, ctx: VulkanContext) =
    let hinstance = cast[pointer](GetModuleHandleW(nil))
    let hwnd = cast[pointer](window.hWnd)
    ctx.setPresentWin32Target(hinstance, hwnd)

type WindyRenderBackend* = object
  ## Opaque per-window backend state used by windy + FigDraw integration.
  window*: Window
  when UseMetalBackend and defined(macosx):
    metalLayer*: MetalLayerHandle
  when UseVulkanBackend and defined(macosx):
    vulkanMetalLayer*: MetalLayerHandle

proc setupBackend*(renderer: FigRenderer, window: Window) =
  ## One-time backend hookup between a Windy window and FigDraw renderer.
  renderer.backendState.window = window
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    if renderer.forceOpenGlByEnv():
      renderer.backendState.window.makeContextCurrent()
      discard renderer.applyRuntimeBackendOverride()
  when UseMetalBackend and defined(macosx):
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
        let vkCtx = VulkanContext(renderer.ctx)
        var hasPresentTarget = false
        when defined(macosx):
          let device = MTLCreateSystemDefaultDevice()
          if device.isNil:
            raise newException(ValueError, "Failed to create Metal device for Vulkan")
          renderer.backendState.vulkanMetalLayer =
            attachMetalLayer(window, device, presentsWithTransaction = true)
          vkCtx.setPresentMetalLayer(renderer.backendState.vulkanMetalLayer.layer)
          hasPresentTarget = true
        elif defined(linux) or defined(bsd) or defined(windows):
          attachVulkanSurface(window, vkCtx)
          hasPresentTarget = true
        if not hasPresentTarget:
          raise newException(
            ValueError, "Vulkan present target unavailable for this Windy window"
          )
      except CatchableError as exc:
        when UseOpenGlFallback:
          renderer.useOpenGlFallback(exc.msg)
        else:
          raise exc

proc beginFrame*(renderer: FigRenderer[WindyRenderBackend]) =
  ## Per-frame pre-render backend maintenance.
  when UseMetalBackend and defined(macosx):
    if renderer.backendKind() == rbMetal:
      let window = renderer.backendState.window
      renderer.backendState.metalLayer.updateMetalLayer(window)
  when UseVulkanBackend and defined(macosx):
    if renderer.backendKind() == rbVulkan:
      let window = renderer.backendState.window
      renderer.backendState.vulkanMetalLayer.updateMetalLayer(window)
  when NeedWindyOpenGLContext:
    if renderer.backendKind() == rbOpenGL:
      renderer.backendState.window.makeContextCurrent()

proc endFrame*(renderer: FigRenderer[WindyRenderBackend]) =
  ## Present a frame for backends that need explicit window buffer swap.
  if renderer.backendKind() == rbOpenGL:
    renderer.backendState.window.swapBuffers()
