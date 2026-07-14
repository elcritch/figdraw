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

proc setBackgroundColor(
  layer: CAMetalLayer, color: pointer
) {.objc: "setBackgroundColor:".}

proc setContentsGravity(
  layer: CAMetalLayer, gravity: NSString
) {.objc: "setContentsGravity:".}

proc setContentsScale(layer: CAMetalLayer, scale: CGFloat) {.objc: "setContentsScale:".}
proc setLayerContentsPlacement(
  view: NSView, placement: NSInteger
) {.objc: "setLayerContentsPlacement:".}

proc createGenericRgbColor(
  red, green, blue, alpha: CGFloat
): pointer {.importc: "CGColorCreateGenericRGB".}

proc releaseCgColor(color: pointer) {.importc: "CGColorRelease".}

const LayerContentsPlacementTopLeft = 11.NSInteger
var kCAGravityTopLeft {.importc.}: NSString

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

proc updateDrawableSize(layer: CAMetalLayer, backingWidth, backingHeight: int32) =
  let
    width = safeDrawableDimension(backingWidth)
    height = safeDrawableDimension(backingHeight)
    current = layer.drawableSize()
  if current.width != width or current.height != height:
    layer.setDrawableSize(NSSize(width: width, height: height))

proc backingScale(bounds: NSRect, backingWidth, backingHeight: int32): CGFloat =
  if bounds.size.width > 0:
    return safeDrawableDimension(backingWidth) / bounds.size.width
  if bounds.size.height > 0:
    return safeDrawableDimension(backingHeight) / bounds.size.height
  1.0

proc setResizeBackgroundColor*(
    handle: SiwinMetalLayerHandle, red, green, blue, alpha: float32
) =
  let color =
    createGenericRgbColor(red.CGFloat, green.CGFloat, blue.CGFloat, alpha.CGFloat)
  if color.isNil:
    return
  try:
    withoutLayerActions:
      handle.layer.setBackgroundColor(color)
  finally:
    releaseCgColor(color)

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
  result.hostView.setLayerContentsPlacement(LayerContentsPlacementTopLeft)
  withoutLayerActions:
    let bounds = result.hostView.bounds()
    # Keep the last complete frame pixel-sized while the view grows. Core
    # Animation otherwise stretches it to the new bounds until the next present.
    result.layer.setContentsGravity(kCAGravityTopLeft)
    result.layer.setFrame(bounds)
    result.layer.setContentsScale(backingScale(bounds, backingWidth, backingHeight))
    result.layer.updateDrawableSize(backingWidth, backingHeight)
  result.setResizeBackgroundColor(1.0, 1.0, 1.0, 1.0)

proc updateMetalLayer*(
    handle: SiwinMetalLayerHandle, backingWidth, backingHeight: int32
) =
  withoutLayerActions:
    let bounds = handle.hostView.bounds()
    handle.layer.setFrame(bounds)
    handle.layer.setContentsScale(backingScale(bounds, backingWidth, backingHeight))
    handle.layer.updateDrawableSize(backingWidth, backingHeight)

proc setOpaque*(handle: SiwinMetalLayerHandle, opaque: bool) =
  handle.layer.setOpaque(opaque)
