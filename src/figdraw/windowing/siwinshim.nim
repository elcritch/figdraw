import std/[os, strutils]
import vmath

import ../commons
import ../figrender

const UseSiwinOpenGL = not (UseMetalBackend or UseVulkanBackend)

when not UseSiwinOpenGL:
  {.error: "siwinshim only supports OpenGL; pass -d:figdraw.opengl=on (and disable Metal/Vulkan).".}

when defined(macosx):
  import std/importutils
  import siwin/platforms/any/window as siAnyWindow
  import siwin/platforms/cocoa/window as siCocoaWindow
  import siwin/platforms/cocoa/cocoa as siCocoa
else:
  {.error: "siwinshim: unsupported OS".}

export siAnyWindow, siCocoaWindow, vmath

privateAccess(WindowCocoaObj)

proc siwinBackendName*(): string =
  backendName(PreferredBackendKind)

proc siwinBackendName*[BackendState](renderer: FigRenderer[BackendState]): string =
  renderer.backendName()

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: " & siwinBackendName() & " + " & suffix

proc newSiwinWindow*(
    size: IVec2,
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
): Window =
  let window = newOpenglWindowCocoa(size = size, title = title, vsync = vsync, msaa = msaa)
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
