import unicode, vmath, windy/common

import ./commons

const UseWindyOpenGL = not (UseMetalBackend or UseVulkanBackend)

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

when UseWindyOpenGL:
  import figdraw/utils/glutils

export common, platform, unicode, vmath

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

  when UseWindyOpenGL:
    startOpenGL(openglVersion)

  when not defined(emscripten):
    if fullscreen:
      window.fullscreen = true
    else:
      window.size = size
    window.visible = true
  when UseWindyOpenGL:
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
