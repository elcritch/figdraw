import unicode, vmath, windy/common

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
  when defined(feature.figdraw.metal):
    import metalx/[cametal, metal, view]
elif defined(linux) or defined(bsd):
  import windy/platforms/linux/platform
else:
  {.error: "windyshim: unsupported OS".}

export common, platform, unicode, vmath

when defined(macosx) and not compiles(cocoaWindow(Window())):
  privateAccess(Window)
  proc cocoaWindow*(window: Window): NSWindow =
    cast[NSWindow](cast[pointer](window.inner.int))

  proc cocoaContentView*(window: Window): NSView =
    cocoaWindow(window).contentView()

when defined(macosx) and defined(feature.figdraw.metal):
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
