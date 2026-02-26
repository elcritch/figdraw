import std/[os, strutils]
when defined(linux) or defined(bsd):
  import std/osproc
import vmath

import siwin/[window as siWindow, windowOpengl as siWindowOpengl]
import siwin/platforms

import ../commons
import ../figrender

const UseSiwinOpenGL = not (UseMetalBackend or UseVulkanBackend)
const NeedSiwinOpenGLContext = UseSiwinOpenGL or UseOpenGlFallback

when defined(macosx):
  import darwin/app_kit/[nsview]
  import siwin/platforms/cocoa/window as siCocoaWindow
  when UseMetalBackend:
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

when defined(linux) or defined(bsd):
  var cachedXftScale {.threadvar.}: float32
  var cachedXftScaleInitialized {.threadvar.}: bool

  proc xftDpiScale(): float32 =
    ## Xft.dpi gives a useful fractional scale for X11 and many XWayland sessions.
    ## Cache once per thread to avoid shelling out repeatedly.
    if cachedXftScaleInitialized:
      return cachedXftScale
    cachedXftScaleInitialized = true
    cachedXftScale = 0.0
    if getEnv("DISPLAY").len == 0:
      return cachedXftScale
    try:
      let output = execProcess("xrdb -query")
      for line in output.splitLines():
        let trimmed = line.strip()
        if not trimmed.toLowerAscii().startsWith("xft.dpi:"):
          continue
        let parts = trimmed.split(":", maxsplit = 1)
        if parts.len != 2:
          break
        let dpi = parts[1].strip().parseFloat()
        if dpi > 0:
          cachedXftScale = (dpi / 96.0).float32
        break
    except CatchableError:
      discard
    cachedXftScale

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
    size: IVec2, fullscreen = false, title = "FigDraw", vsync = true, msaa = 0'i32
): Window =
  let forceOpenGl = runtimeForceOpenGlRequested()
  let window =
    when UseMetalBackend and not NeedSiwinOpenGLContext:
      when defined(macosx):
        newMetalWindowCocoa(size = size, title = title)
      else:
        {.error: "siwinshim: Metal backend requires macOS".}
    else:
      when defined(macosx):
        newOpenglWindowCocoa(size = size, title = title, vsync = vsync, msaa = msaa)
      else:
        let globals = sharedSiwinGlobals()
        when UseVulkanBackend:
          if forceOpenGl:
            newOpenglWindow(globals, size = size, title = title, vsync = vsync)
          else:
            # Use a non-GL window for Vulkan so siwin's GL swap path does not flicker.
            newSoftwareRenderingWindow(globals, size = size, title = title)
        else:
          newOpenglWindow(globals, size = size, title = title, vsync = vsync)
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
): Window =
  ## Compatibility overload. Prefer creating a window first, then renderer.
  let forceOpenGl = runtimeForceOpenGlRequested() or renderer.forceOpenGlByEnv()
  when UseVulkanBackend:
    if not forceOpenGl and renderer.backendKind() == rbVulkan:
      let globals = sharedSiwinGlobals()
      let vkCtx = renderer.ctx.VulkanContext
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
      elif defined(macosx):
        vkCtx.setInstanceSurfaceHint(presentTargetMetal)
      vkCtx.ensureInstance()
      result = siWindowVulkan.newVulkanWindow(
        globals,
        vkCtx.instanceHandle(),
        size = size,
        title = title,
        fullscreen = fullscreen,
      )
      if fullscreen:
        result.fullscreen = true
      return

  discard renderer
  result = newSiwinWindow(
    size = size, fullscreen = fullscreen, title = title, vsync = vsync, msaa = msaa
  )

proc backingSize*(window: Window): IVec2 =
  when defined(macosx):
    let contentView = cast[NSView](WindowCocoa(window).nativeViewHandle())
    let frame = contentView.frame
    let backing = contentView.convertRectToBacking(frame)
    ivec2(backing.size.width.int32, backing.size.height.int32)
  else:
    when defined(linux) or defined(bsd):
      let size = window.size
      if window of siWaylandWindow.WindowWayland:
        let scale = window.uiScale()
        if scale > 1.0:
          ivec2(
            max(1'i32, (size.x.float32 * scale + 0.5'f32).int32),
            max(1'i32, (size.y.float32 * scale + 0.5'f32).int32),
          )
        else:
          size
      else:
        size
    else:
      window.size

proc logicalSize*(window: Window): Vec2 =
  vec2(window.backingSize()).descaled()

proc contentScale*(window: Window): float32 =
  when defined(macosx):
    let contentView = cast[NSView](WindowCocoa(window).nativeViewHandle())
    let frame = contentView.frame
    if frame.size.width <= 0:
      return 1.0
    let backing = contentView.convertRectToBacking(frame)
    (backing.size.width / frame.size.width).float32
  elif defined(linux) or defined(bsd):
    let backendScale = window.uiScale()
    let scale = if backendScale > 0: backendScale else: 1.0
    let xftScale = xftDpiScale()
    if xftScale > 0:
      if window of siX11Window.WindowX11:
        return xftScale
    scale
  else:
    1.0

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

when UseMetalBackend and defined(macosx):
  type MetalLayerHandle* = siwinmetal.SiwinMetalLayerHandle

  proc attachMetalLayer*(
      window: Window,
      device: siwinmetal.MTLDevice,
      pixelFormat: siwinmetal.MTLPixelFormat = siwinmetal.MTLPixelFormatBGRA8Unorm,
  ): MetalLayerHandle =
    ## Attaches a CAMetalLayer to a siwin macOS window.
    let sz = window.backingSize()
    result = siwinmetal.attachMetalLayerToWindowPtr(
      WindowCocoa(window).nativeWindowHandle(), sz.x, sz.y, device, pixelFormat
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
  when UseMetalBackend and defined(macosx):
    metalLayer*: MetalLayerHandle

proc setupBackend*(renderer: FigRenderer, window: Window) =
  ## One-time backend hookup between a siwin window and FigDraw renderer.
  renderer.backendState.window = window
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
      except CatchableError as exc:
        when UseOpenGlFallback:
          renderer.useOpenGlFallback(exc.msg)
        else:
          raise exc
  when UseVulkanBackend:
    if renderer.backendKind() == rbVulkan:
      let vkCtx = renderer.ctx.VulkanContext
      var hasPresentTarget = false
      when defined(linux) or defined(bsd):
        if window of siX11Window.WindowX11SoftwareRendering:
          siX11Window.WindowX11SoftwareRendering(window).setSoftwarePresentEnabled(
            false
          )
      let surface = window.vulkanSurface()
      if not surface.isNil:
        when defined(linux) or defined(bsd):
          if window of siWaylandWindow.WindowWayland:
            vkCtx.setExternalSurface(
              surface, presentTargetWayland, ownedByContext = true
            )
            hasPresentTarget = true
          else:
            vkCtx.setExternalSurface(surface, presentTargetXlib, ownedByContext = true)
            hasPresentTarget = true
        elif defined(windows):
          vkCtx.setExternalSurface(surface, presentTargetWin32, ownedByContext = true)
          hasPresentTarget = true
        elif defined(macosx):
          vkCtx.setExternalSurface(surface, presentTargetMetal, ownedByContext = true)
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

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## Per-frame pre-render backend maintenance.
  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    if renderer.forceOpenGlByEnv() and renderer.backendKind() != rbOpenGL:
      when NeedSiwinOpenGLContext:
        renderer.backendState.window.makeCurrent()
      discard renderer.applyRuntimeBackendOverride()
  when UseMetalBackend and defined(macosx):
    if renderer.backendKind() == rbMetal:
      let window = renderer.backendState.window
      renderer.backendState.metalLayer.updateMetalLayer(window)
  when NeedSiwinOpenGLContext:
    if renderer.backendKind() == rbOpenGL:
      renderer.backendState.window.makeCurrent()

proc endFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  ## siwin's step() already flushes OpenGL buffers after onRender callbacks.
  ## Avoid explicit swapping here to prevent double-buffer flips/flicker.
  discard
