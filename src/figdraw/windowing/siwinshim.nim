import std/[math, os, strutils]
import pkg/chroma
import vmath

import siwin/[window as siWindow, windowOpengl as siWindowOpengl]
import siwin/platforms

import ../commons
import ../fignodes
import ../figrender

const UseSiwinOpenGL = not (UseMetalBackend or UseVulkanBackend)
const NeedSiwinOpenGLContext = UseSiwinOpenGL or UseOpenGlFallback

when defined(macosx):
  import darwin/app_kit/[nscolor, nsview, nswindow]
  import darwin/objc/runtime
  import siwin/platforms/cocoa/window as siCocoaWindow
  when UseMetalBackend or UseVulkanBackend:
    import ./siwinmetal as siwinmetal
when defined(linux) or defined(bsd):
  import siwin/platforms/x11/window as siX11Window
  import siwin/platforms/wayland/window as siWaylandWindow
when UseVulkanBackend:
  import siwin/windowVulkan as siWindowVulkan
  import ../vulkan/vulkan_context

when NeedSiwinOpenGLContext:
  import figdraw/utils/glutils

export siWindow, siWindowOpengl, vmath
when defined(macosx):
  export siCocoaWindow

proc siwinBackendName*(): string =
  backendName(PreferredBackendKind)

proc siwinBackendName*[BackendState](renderer: FigRenderer[BackendState]): string =
  renderer.backendName()

var siwinGlobalsShared {.threadvar.}: SiwinGlobals

proc sharedSiwinGlobals*(): SiwinGlobals =
  if siwinGlobalsShared.isNil:
    siwinGlobalsShared = newSiwinGlobals()
  siwinGlobalsShared

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: " & siwinBackendName() & " + " & suffix

proc siwinDisplayServerName*(window: Window): string =
  when defined(linux) or defined(bsd):
    if window of siX11Window.WindowX11:
      "x11"
    elif window of siWaylandWindow.WindowWayland:
      "wayland"
    else:
      "unknown"
  else:
    ""

proc siwinWindowTitle*[BackendState](
    renderer: FigRenderer[BackendState], window: Window, suffix = "Siwin RenderList"
): string =
  let backend = renderer.backendName()
  let display = window.siwinDisplayServerName()
  when defined(linux) or defined(bsd):
    "figdraw: " & backend & " + " & display & " + " & suffix
  else:
    "figdraw: " & backend & " + " & suffix

proc newSiwinWindow*(
    size: IVec2,
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
    resizable = true,
    frameless = false,
    transparent = false,
): Window =
  let forceOpenGl = runtimeForceOpenGlRequested()
  let window =
    when defined(macosx):
      when UseVulkanBackend:
        if forceOpenGl:
          newOpenglWindowCocoa(
            size = size,
            title = title,
            vsync = vsync,
            msaa = msaa,
            resizable = resizable,
            frameless = frameless,
            transparent = transparent,
          )
        else:
          # Vulkan presents through CAMetalLayer. Avoid NSOpenGLView here because
          # siwin swaps GL buffers after onRender callbacks, which can blank the
          # Metal subview during live resize.
          newMetalWindowCocoa(
            size = size,
            title = title,
            resizable = resizable,
            frameless = frameless,
            transparent = transparent,
          )
      elif UseMetalBackend and not NeedSiwinOpenGLContext:
        newMetalWindowCocoa(
          size = size,
          title = title,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
      else:
        newOpenglWindowCocoa(
          size = size,
          title = title,
          vsync = vsync,
          msaa = msaa,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
    else:
      when UseMetalBackend and not NeedSiwinOpenGLContext:
        {.error: "siwinshim: Metal backend requires macOS".}
      else:
        let globals = sharedSiwinGlobals()
        when UseVulkanBackend:
          if forceOpenGl:
            newOpenglWindow(
              globals,
              size = size,
              title = title,
              vsync = vsync,
              resizable = resizable,
              frameless = frameless,
              transparent = transparent,
            )
          else:
            # Use a non-GL window for Vulkan so siwin's GL swap path does not flicker.
            newSoftwareRenderingWindow(
              globals,
              size = size,
              title = title,
              resizable = resizable,
              frameless = frameless,
              transparent = transparent,
            )
        else:
          newOpenglWindow(
            globals,
            size = size,
            title = title,
            vsync = vsync,
            resizable = resizable,
            frameless = frameless,
            transparent = transparent,
          )
  when NeedSiwinOpenGLContext:
    when UseVulkanBackend:
      if forceOpenGl:
        startOpenGL(openglVersion)
        window.makeCurrent()
    else:
      startOpenGL(openglVersion)
      window.makeCurrent()
  if fullscreen:
    window.fullscreen = true
  result = window

proc newSiwinWindow*(
    renderer: FigRenderer,
    size: IVec2,
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
    resizable = true,
    frameless = false,
    transparent = false,
): Window =
  ## Compatibility overload. Prefer creating a window first, then renderer.
  let forceOpenGl = runtimeForceOpenGlRequested() or renderer.forceOpenGlByEnv()
  when UseVulkanBackend:
    if not forceOpenGl and renderer.backendKind() == rbVulkan:
      when defined(macosx):
        return newSiwinWindow(
          size = size,
          fullscreen = fullscreen,
          title = title,
          vsync = vsync,
          msaa = msaa,
          resizable = resizable,
          frameless = frameless,
          transparent = transparent,
        )
      else:
        let
          vkCtx = renderer.ctx.VulkanContext
          globals = sharedSiwinGlobals()
        when defined(linux) or defined(bsd):
          case defaultPreferedPlatform()
          of Platform.wayland:
            vkCtx.setInstanceSurfaceHint(presentTargetWayland)
          of Platform.x11:
            vkCtx.setInstanceSurfaceHint(presentTargetXlib)
          else:
            discard
        elif defined(windows):
          vkCtx.setInstanceSurfaceHint(presentTargetWin32)
        vkCtx.ensureInstance()
        result = siWindowVulkan.newVulkanWindow(
          globals,
          vkCtx.instanceHandle(),
          size = size,
          title = title,
          resizable = resizable,
          fullscreen = fullscreen,
          frameless = frameless,
          transparent = transparent,
        )
        if fullscreen:
          result.fullscreen = true
        return

  discard renderer
  result = newSiwinWindow(
    size = size,
    fullscreen = fullscreen,
    title = title,
    vsync = vsync,
    msaa = msaa,
    resizable = resizable,
    frameless = frameless,
    transparent = transparent,
  )

proc backingSize*(window: Window): IVec2 =
  when defined(macosx):
    let contentView = cast[NSView](WindowCocoa(window).nativeViewHandle())
    let backing = contentView.convertRectToBacking(contentView.bounds())
    ivec2(
      max(0'i32, ceil(backing.size.width).int32),
      max(0'i32, ceil(backing.size.height).int32),
    )
  else:
    window.size

proc inputUsesBackingPixels*(window: Window): bool =
  when defined(macosx):
    not window.isNil
  elif defined(linux) or defined(bsd):
    window of siWaylandWindow.WindowWayland
  else:
    false

proc inputDeviceScale*(window: Window): float32

proc logicalSize*(window: Window): Vec2 =
  if window.isNil:
    return vec2(0.0'f32, 0.0'f32)
  if window.inputUsesBackingPixels():
    let scale = window.inputDeviceScale()
    let backing = window.backingSize()
    return vec2(backing.x.float32 / scale, backing.y.float32 / scale)
  vec2(window.size)

proc contentScale*(window: Window): float32 =
  when defined(macosx):
    let contentView = cast[NSView](WindowCocoa(window).nativeViewHandle())
    let bounds = contentView.bounds()
    if bounds.size.width <= 0:
      return 1.0
    let backing = contentView.convertRectToBacking(bounds)
    (backing.size.width / bounds.size.width).float32
  elif defined(linux) or defined(bsd):
    let backendScale = window.uiScale()
    let scale = if backendScale > 0: backendScale else: 1.0
    scale
  else:
    1.0

proc inputDeviceScale*(window: Window): float32 =
  if window.isNil:
    return 1.0'f32
  let scale = window.contentScale()
  if scale > 0.0'f32:
    return scale
  1.0'f32

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
  when defined(macosx):
    if window of WindowCocoaOpengl:
      WindowCocoaOpengl(window).swapBuffers()

when (UseMetalBackend or UseVulkanBackend) and defined(macosx):
  type MetalLayerHandle* = siwinmetal.SiwinMetalLayerHandle

  proc attachMetalLayer*(
      window: Window,
      device: siwinmetal.MTLDevice,
      pixelFormat: siwinmetal.MTLPixelFormat = siwinmetal.MTLPixelFormatBGRA8Unorm,
      presentsWithTransaction = false,
  ): MetalLayerHandle =
    ## Attaches a CAMetalLayer to a siwin macOS window.
    let sz = window.backingSize()
    result = siwinmetal.attachMetalLayerToWindowPtr(
      WindowCocoa(window).nativeWindowHandle(),
      sz.x,
      sz.y,
      device,
      pixelFormat,
      presentsWithTransaction,
    )

  proc updateMetalLayer*(handle: MetalLayerHandle, window: Window) =
    ## Updates layer frame + drawable size (call on resize/redraw).
    let sz = window.backingSize()
    siwinmetal.updateMetalLayer(handle, sz.x, sz.y)

  proc setOpaque*(handle: MetalLayerHandle, opaque: bool) =
    ## Controls CAMetalLayer opacity without exposing Objective-C details.
    siwinmetal.setOpaque(handle, opaque)

type
  SiwinRenderBackend* = object
    ## Opaque per-window backend state used by siwin + FigDraw integration.
    window*: Window
    dedicatedRender*: bool
    presentationReady: bool
    resizeClearColor: Color
    resizeClearColorSet: bool
    when UseMetalBackend and defined(macosx):
      metalLayer*: MetalLayerHandle
    when UseVulkanBackend and defined(macosx):
      vulkanMetalLayer*: MetalLayerHandle

  SiwinPresentationTarget* = object
    ## Main-thread-owned presentation state for a renderer that encodes frames
    ## on another thread. The renderer retains its own copy of the Metal layer;
    ## this value exists solely so the window host can keep its geometry current.
    when UseMetalBackend and defined(macosx):
      metalLayer*: MetalLayerHandle
    when UseVulkanBackend and defined(macosx):
      vulkanMetalLayer*: MetalLayerHandle

when defined(macosx):
  proc setOpaque(window: NSWindow, opaque: BOOL) {.objc: "setOpaque:".}

proc syncResizeBackgroundColor(
    renderer: FigRenderer[SiwinRenderBackend], color: Color
) =
  if renderer.backendState.resizeClearColorSet and
      renderer.backendState.resizeClearColor == color:
    return

  when defined(macosx):
    when UseMetalBackend:
      let handle = renderer.backendState.metalLayer
      if not handle.layer.isNil:
        handle.setResizeBackgroundColor(color.r, color.g, color.b, color.a)
    when UseVulkanBackend:
      let handle = renderer.backendState.vulkanMetalLayer
      if not handle.layer.isNil:
        handle.setResizeBackgroundColor(color.r, color.g, color.b, color.a)

  renderer.backendState.resizeClearColor = color
  renderer.backendState.resizeClearColorSet = true

proc configureTransparentPresentation*(
    renderer: FigRenderer[SiwinRenderBackend], window: Window
) =
  if window.isNil or not window.transparent:
    return
  when defined(macosx):
    if window of WindowCocoa:
      let nativeWindow = cast[NSWindow](WindowCocoa(window).nativeWindowHandle())
      if not nativeWindow.isNil:
        nativeWindow.setOpaque(false)
        nativeWindow.setBackgroundColor(NSColor.clearColor())
    when UseMetalBackend:
      if not renderer.backendState.metalLayer.layer.isNil:
        renderer.backendState.metalLayer.setOpaque(false)
    when UseVulkanBackend:
      if not renderer.backendState.vulkanMetalLayer.layer.isNil:
        renderer.backendState.vulkanMetalLayer.setOpaque(false)

proc presentationTarget*(
    renderer: FigRenderer[SiwinRenderBackend]
): SiwinPresentationTarget =
  when UseMetalBackend and defined(macosx):
    result.metalLayer = renderer.backendState.metalLayer
  when UseVulkanBackend and defined(macosx):
    result.vulkanMetalLayer = renderer.backendState.vulkanMetalLayer

proc updatePresentationTarget*(target: SiwinPresentationTarget, window: Window) =
  ## Update the native layer from the thread which owns the window. Rendering
  ## may subsequently acquire its drawable and encode commands elsewhere.
  when UseMetalBackend and defined(macosx):
    if not target.metalLayer.layer.isNil and not window.isNil:
      target.metalLayer.updateMetalLayer(window)
  when UseVulkanBackend and defined(macosx):
    if not target.vulkanMetalLayer.layer.isNil and not window.isNil:
      target.vulkanMetalLayer.updateMetalLayer(window)

func backendSupportsDedicatedRenderThread*(kind: RendererBackendKind): bool =
  ## Whether this build can present this backend from a dedicated thread.
  case kind
  of rbMetal:
    when UseMetalBackend and defined(macosx): true else: false
  of rbVulkan:
    when UseVulkanBackend: true else: false
  of rbOpenGL:
    false

proc supportsDedicatedRenderThread*(renderer: FigRenderer[SiwinRenderBackend]): bool =
  ## Whether the configured presentation backend can be detached from its
  ## native window. OpenGL remains bound to the window and platform thread.
  if renderer.isNil or renderer.ctx.isNil or not renderer.backendState.presentationReady:
    return false
  if not backendSupportsDedicatedRenderThread(renderer.backendKind()):
    return false
  case renderer.backendKind()
  of rbMetal:
    when UseMetalBackend and defined(macosx):
      return not renderer.backendState.metalLayer.layer.isNil
    else:
      discard
  of rbVulkan:
    when UseVulkanBackend:
      when defined(macosx):
        return not renderer.backendState.vulkanMetalLayer.layer.isNil
      else:
        return true
    else:
      discard
  of rbOpenGL:
    discard

proc useDedicatedRenderThread*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## Marks this renderer as owned by a dedicated render thread after the window
  ## thread has attached and configured its presentation target. Do not retain
  ## the native window across the ownership boundary: its lifetime remains on
  ## the platform thread.
  if not renderer.supportsDedicatedRenderThread():
    raise newException(
      ValueError, "the active siwin backend cannot render on a dedicated thread"
    )
  renderer.backendState.dedicatedRender = true
  renderer.backendState.window = nil

proc setupBackend*(renderer: FigRenderer, window: Window) =
  ## One-time backend hookup between a siwin window and FigDraw renderer.
  renderer.backendState.window = window
  renderer.backendState.dedicatedRender = false
  renderer.backendState.presentationReady = false
  renderer.backendState.resizeClearColorSet = false
  renderer.configureTransparentPresentation(window)
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    if renderer.forceOpenGlByEnv():
      when NeedSiwinOpenGLContext:
        window.makeCurrent()
      try:
        # Prefer switching immediately so setup-time backend queries/title reflect
        # the forced backend. If context is not fully ready yet, beginFrame() will
        # retry.
        discard renderer.applyRuntimeBackendOverride()
      except CatchableError:
        # Defer actual backend swap to beginFrame(). Wayland OpenGL contexts can
        # still require the first render-cycle entry.
        return
  when UseMetalBackend and defined(macosx):
    if renderer.backendKind() == rbMetal:
      try:
        renderer.backendState.metalLayer =
          attachMetalLayer(window, renderer.ctx.metalDevice())
        renderer.ctx.setPresentLayer(renderer.backendState.metalLayer.layer)
        renderer.backendState.presentationReady = true
      except CatchableError as exc:
        when UseOpenGlFallback:
          renderer.useOpenGlFallback(exc.msg)
        else:
          raise exc
  when UseVulkanBackend:
    if renderer.backendKind() == rbVulkan:
      try:
        let vkCtx = renderer.ctx.VulkanContext
        var hasPresentTarget = false
        when defined(macosx):
          let device = siwinmetal.MTLCreateSystemDefaultDevice()
          if device.isNil:
            raise newException(ValueError, "Failed to create Metal device for Vulkan")
          renderer.backendState.vulkanMetalLayer =
            attachMetalLayer(window, device, presentsWithTransaction = false)
          vkCtx.setPresentMetalLayer(renderer.backendState.vulkanMetalLayer.layer)
          hasPresentTarget = true
        elif defined(linux) or defined(bsd):
          var surface: pointer = nil
          if window of siX11Window.WindowX11SoftwareRendering:
            siX11Window.WindowX11SoftwareRendering(window).setSoftwarePresentEnabled(
              false
            )
          surface = window.vulkanSurface()
          if not surface.isNil:
            if window of siWaylandWindow.WindowWayland:
              vkCtx.setExternalSurface(
                surface, presentTargetWayland, ownedByContext = true
              )
              hasPresentTarget = true
            else:
              vkCtx.setExternalSurface(
                surface, presentTargetXlib, ownedByContext = true
              )
              hasPresentTarget = true
        elif defined(windows):
          let surface = window.vulkanSurface()
          if not surface.isNil:
            vkCtx.setExternalSurface(surface, presentTargetWin32, ownedByContext = true)
            hasPresentTarget = true
        when defined(linux) or defined(bsd):
          if surface.isNil and window of siX11Window.WindowX11:
            let x11Window = siX11Window.WindowX11(window)
            vkCtx.setPresentXlibTarget(
              x11Window.nativeDisplayHandle(), x11Window.nativeWindowHandle()
            )
            hasPresentTarget = true
        if not hasPresentTarget:
          raise newException(
            ValueError,
            "Vulkan present target unavailable for this siwin window (Wayland/X11 mismatch)",
          )
        renderer.backendState.presentationReady = true
      except CatchableError as exc:
        when UseOpenGlFallback:
          renderer.useOpenGlFallback(exc.msg)
        else:
          raise exc
  renderer.configureTransparentPresentation(window)
  renderer.syncResizeBackgroundColor(if window.transparent: clearColor else: whiteColor)

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## Per-frame pre-render backend maintenance.
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    if renderer.forceOpenGlByEnv() and renderer.backendKind() != rbOpenGL:
      when NeedSiwinOpenGLContext:
        renderer.backendState.window.makeCurrent()
      discard renderer.applyRuntimeBackendOverride()
  when UseMetalBackend and defined(macosx):
    if not renderer.backendState.dedicatedRender and renderer.backendKind() == rbMetal:
      let window = renderer.backendState.window
      renderer.backendState.metalLayer.updateMetalLayer(window)
  when UseVulkanBackend and defined(macosx):
    if not renderer.backendState.dedicatedRender and renderer.backendKind() == rbVulkan:
      let window = renderer.backendState.window
      renderer.backendState.vulkanMetalLayer.updateMetalLayer(window)
  when NeedSiwinOpenGLContext:
    if renderer.backendKind() == rbOpenGL:
      renderer.backendState.window.makeCurrent()

proc endFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## siwin's step() already flushes OpenGL buffers after onRender callbacks.
  ## Avoid explicit swapping here to prevent double-buffer flips/flicker.
  discard

proc renderFrame*(
    renderer: FigRenderer[SiwinRenderBackend],
    nodes: var Renders,
    frameSize: Vec2,
    clearMain = true,
    clearColor: Color = whiteColor,
) =
  ## Renders a frame and uses its clear color for uncovered resize areas.
  if clearMain:
    if renderer.backendState.dedicatedRender:
      renderer.backendState.resizeClearColor = clearColor
      renderer.backendState.resizeClearColorSet = true
    else:
      renderer.syncResizeBackgroundColor(clearColor)
  figrender.renderFrame(
    renderer,
    nodes,
    frameSize,
    clearMain = clearMain,
    clearColor = clearColor,
    allowOpenGlFallback = not renderer.backendState.dedicatedRender,
  )
