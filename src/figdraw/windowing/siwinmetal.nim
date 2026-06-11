import ../commons

when (UseMetalBackend or UseVulkanBackend) and defined(macosx):
  import darwin/app_kit/[nswindow, nsview]
  import darwin/core_graphics/cggeometry
  import darwin/foundation/nsgeometry
  import darwin/objc/runtime
  import metalx/[cametal, metal, view]
else:
  {.error: "siwinmetal: macOS Metal only".}

export cametal, metal

type SiwinMetalLayerHandle* = object
  ## Thin container around the host NSView + CAMetalLayer.
  hostView*: NSView
  layer*: CAMetalLayer

proc setOpaque(layer: CAMetalLayer, opaque: bool) {.objc: "setOpaque:".}
proc setContentsScale(layer: CAMetalLayer, scale: CGFloat) {.objc: "setContentsScale:".}

proc safeDrawableDimension(v: int32): float =
  # CAMetalLayer rejects zero-sized drawables; clamp transient 0x0 resize states.
  max(1'i32, v).float

proc backingScale(bounds: NSRect, backingWidth, backingHeight: int32): CGFloat =
  if bounds.size.width > 0:
    return safeDrawableDimension(backingWidth) / bounds.size.width
  if bounds.size.height > 0:
    return safeDrawableDimension(backingHeight) / bounds.size.height
  1.0

proc attachMetalLayerToWindowPtr*(
    windowPtr: pointer,
    backingWidth, backingHeight: int32,
    device: MTLDevice,
    pixelFormat: MTLPixelFormat = MTLPixelFormatBGRA8Unorm,
): SiwinMetalLayerHandle =
  let window = cast[NSWindow](windowPtr)
  result.hostView = attachMetalHostView(window)
  result.layer = CAMetalLayer.alloc().init()
  result.layer.setDevice(device)
  result.layer.setPixelFormat(pixelFormat)
  result.hostView.setLayer(result.layer)
  let bounds = result.hostView.bounds()
  result.layer.setFrame(bounds)
  result.layer.setContentsScale(backingScale(bounds, backingWidth, backingHeight))
  result.layer.setDrawableSize(
    NSSize(
      width: safeDrawableDimension(backingWidth),
      height: safeDrawableDimension(backingHeight),
    )
  )

proc updateMetalLayer*(
    handle: SiwinMetalLayerHandle, backingWidth, backingHeight: int32
) =
  let bounds = handle.hostView.bounds()
  handle.layer.setFrame(bounds)
  handle.layer.setContentsScale(backingScale(bounds, backingWidth, backingHeight))
  handle.layer.setDrawableSize(
    NSSize(
      width: safeDrawableDimension(backingWidth),
      height: safeDrawableDimension(backingHeight),
    )
  )

proc setOpaque*(handle: SiwinMetalLayerHandle, opaque: bool) =
  handle.layer.setOpaque(opaque)
