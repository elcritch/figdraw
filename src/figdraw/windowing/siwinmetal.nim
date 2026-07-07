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

type CATransaction = ptr object of NSObject

proc begin(t: typedesc[CATransaction]) {.objc: "begin".}
proc commit(t: typedesc[CATransaction]) {.objc: "commit".}
proc setDisableActions(
  t: typedesc[CATransaction], disabled: bool
) {.objc: "setDisableActions:".}

proc setOpaque(layer: CAMetalLayer, opaque: bool) {.objc: "setOpaque:".}
proc setPresentsWithTransaction(
  layer: CAMetalLayer, enabled: bool
) {.objc: "setPresentsWithTransaction:".}

proc setContentsScale(layer: CAMetalLayer, scale: CGFloat) {.objc: "setContentsScale:".}

template withoutLayerActions(body: untyped) =
  CATransaction.begin()
  CATransaction.setDisableActions(true)
  try:
    body
  finally:
    CATransaction.commit()

proc safeDrawableDimension(v: int32): CGFloat =
  # CAMetalLayer rejects zero-sized drawables; clamp transient 0x0 resize states.
  max(1'i32, v).CGFloat

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
    presentsWithTransaction = false,
): SiwinMetalLayerHandle =
  let window = cast[NSWindow](windowPtr)
  result.hostView = attachMetalHostView(window)
  result.layer = CAMetalLayer.alloc().init()
  result.layer.setDevice(device)
  result.layer.setPixelFormat(pixelFormat)
  result.layer.setOpaque(true)
  result.layer.setPresentsWithTransaction(presentsWithTransaction)
  result.hostView.setLayer(result.layer)
  withoutLayerActions:
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
  withoutLayerActions:
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
