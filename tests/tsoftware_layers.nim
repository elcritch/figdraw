import std/[hashes, unittest, importutils]
import pkg/[pixie, chroma, vmath]
import figdraw/[commons, figbackend, fignodes, figrender]
import figdraw/software/[context, layers]
import ../examples/renderlist_100_common

type ComposedFrame = ref object
  image: Image
  layers: seq[Image]
  bounds: seq[Rect]

privateAccess ImageLayerContext

proc newContext(
    frame: ComposedFrame, native = false, maxCacheBytes: Positive = 64 * 1024 * 1024
): ImageLayerContext =
  var composer = ImageComposer(
    coordinateScale: 1,
    beginFrame: proc(size: Vec2, clear: bool, color: Color) =
      if frame.image.isNil or frame.image.width != size.x.int or
          frame.image.height != size.y.int:
        frame.image = newImage(size.x.int, size.y.int)
      if clear:
        frame.image.fill(color)
      frame.layers.setLen(0)
      frame.bounds.setLen(0),
    drawImage: proc(layer: LayerImage, bounds: Rect) =
      frame.layers.add(layer.image)
      frame.bounds.add(bounds)
      frame.image.draw(layer.image, translate(bounds.xy)),
    snapshot: proc(): Image =
      frame.image.copy(),
  )
  if native:
    composer.snapshot = nil
  newImageLayerContext(composer, workers = 1, maxCacheBytes = maxCacheBytes)

proc begin(ctx: BackendContext, clear = true) =
  ctx.beginFrame(vec2(64), clear, color(0, 0, 0, 0))

proc radii(): CornerRadii2D[float32] =
  result.x = [5'f32, 8, 3, 6]
  result.y = [3'f32, 4, 6, 8]

suite "cached software image layers":
  test "translation-only Retina renderlist reuses all cached image layers":
    let oldScale = figUiScale()
    defer:
      setFigUiScale(oldScale)
    setFigUiScale(2)
    let compositor = ImageComposer(
      coordinateScale: 2,
      packedPixels: true,
      beginFrame: proc(size: Vec2, clear: bool, fill: Color) =
        discard,
      drawImage: proc(layer: LayerImage, bounds: Rect) =
        discard,
    )
    let ctx = newImageLayerContext(compositor, maxCacheBytes = 128 * 1024 * 1024)
    let renderer = newFigRenderer(ctx)
    for size in [vec2(800, 600), vec2(1728, 1117), vec2(3000, 2000)]:
      # Resizing can create new edge-cropped rasters, then motion must reuse
      # them even when a window-sized image would exceed the entire cache.
      for frame in [1, 2, 40, 100, 300]:
        var scene = makeRenderTree(
          size.x, size.y, frame, 10, false, false, includeBackground = false
        )
        renderer.renderFrame(scene, size)
        let stats = ctx.imageCacheStats()
        check stats.bytes <= 128 * 1024 * 1024
        if frame != 1:
          check stats.misses == 0
          check stats.hits > 0

  test "an oversized image does not evict reusable images it cannot replace":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true, maxCacheBytes = 512)
    ctx.begin()
    ctx.drawRect(rect(4, 5, 8, 8), color(1, 0, 0, 1))
    let cached = frame.layers[0]
    ctx.drawRect(rect(0, 0, 64, 64), color(0, 0, 1, 1))
    check ctx.imageCacheStats().entries == 1
    check ctx.imageCacheStats().bytes == 256
    ctx.begin()
    ctx.drawRect(rect(4, 5, 8, 8), color(1, 0, 0, 1))
    check frame.layers[0] == cached
    check ctx.imageCacheStats().hits == 1
    check ctx.imageCacheStats().misses == 0

  test "capture references do not retain rasters evicted by the cache budget":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true, maxCacheBytes = 512)
    ctx.begin()
    for i in 0 ..< 3:
      ctx.drawRect(rect(i.float32 * 10, 0, 8, 8), color(i.float32 / 2, 0, 0, 1))
    check ctx.cacheBytes <= 512
    check ctx.captured.len == 0
    check not ctx.captureValid
    check frame.image[20, 0].r == 255
    expect ValueError:
      discard ctx.readPixels(rect(0, 0, 0, 0), false)

  test "internal raster does not subscribe to global image updates":
    let ctx = ComposedFrame().newContext()
    check ctx.imageMessages != nil
    check ctx.raster.imageMessages == nil

  test "native captures retain image revisions after source updates and removal":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true)
    let image = newImage(2, 2)
    image.fill(rgba(255, 0, 0, 255))
    ctx.putImage(42.Hash, image)
    ctx.begin()
    ctx.drawImage(42.Hash, vec2(4), color(1, 1, 1, 1), false)
    image.fill(rgba(0, 255, 0, 255))
    ctx.updateImage(42.Hash, image)
    ctx.drawImage(42.Hash, vec2(12), color(1, 1, 1, 1), false)
    ctx.removeImage(ImageId(42))
    let captured = ctx.readPixels(rect(0, 0, 0, 0), false)
    check captured[4, 4] == rgba(255, 0, 0, 255).rgbx()
    check captured[12, 12] == rgba(0, 255, 0, 255).rgbx()

  test "uncleared native frames draw without reconstructing a software frame":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true)
    ctx.begin()
    ctx.drawRect(rect(4, 4, 8, 8), color(1, 0, 0, 1))
    ctx.begin(clear = false)
    ctx.drawRect(rect(20, 20, 8, 8), color(0, 1, 0, 1))
    check frame.image[4, 4].r == 255
    check frame.image[20, 20].g == 255
    expect ValueError:
      discard ctx.readPixels(rect(0, 0, 0, 0), false)

  test "bounded images are reused and changes invalidate the affected image":
    let frame = ComposedFrame()
    let ctx = frame.newContext()
    ctx.begin()
    ctx.drawRect(rect(4, 5, 8, 9), color(1, 0, 0, 0.5))
    ctx.drawRect(rect(20, 6, 7, 8), color(0, 1, 0, 0.5))
    let first = frame.layers
    check first.len == 2
    check first[0].width == 8
    check first[0].height == 9
    ctx.begin()
    ctx.drawRect(rect(4, 5, 8, 9), color(1, 0, 0, 0.5))
    ctx.drawRect(rect(20, 6, 7, 8), color(0, 0, 1, 0.5))
    check frame.layers[0] == first[0]
    check frame.layers[1] != first[1]
    ctx.begin()
    ctx.drawRect(rect(8, 9, 8, 9), color(1, 0, 0, 0.5))
    check frame.layers[0] == first[0]
    check frame.bounds[0] == rect(8, 9, 8, 9)

  test "the compositor owns scene blending including clipped transformed layers":
    let frame = ComposedFrame()
    let layers = frame.newContext()
    let reference = newSoftwareContext(workers = 1)
    for ctx in [BackendContext(layers), BackendContext(reference)]:
      ctx.begin()
      ctx.drawRect(rect(0, 0, 64, 64), color(0, 0, 1, 1))
      ctx.saveTransform()
      ctx.translate(vec2(11, 7))
      ctx.beginMask(rect(0, 0, 35, 33), radii())
      ctx.endMask()
      ctx.rotate(0.15)
      ctx.drawRoundedRectSdf(
        rect(-4, -3, 39, 40),
        BackendFill(
          kind: bfLinear2,
          lin2Axis: fgaDiagTLBR,
          lin2Start: rgba(255, 0, 0, 128),
          lin2Stop: rgba(0, 255, 0, 180),
        ),
        radii(),
        sdfModeClipAA,
        0,
        0,
        vec2(0),
      )
      ctx.popMask()
      ctx.restoreTransform()
    let expected = reference.readPixels(rect(0, 0, 0, 0), false)
    var error = 0
    for i, actual in frame.image.data:
      let p = expected.data[i]
      error = max(error, abs(actual.r.int - p.r.int))
      error = max(error, abs(actual.g.int - p.g.int))
      error = max(error, abs(actual.b.int - p.b.int))
      error = max(error, abs(actual.a.int - p.a.int))
    check error <= 1

  test "backdrop blur does not add image layers or change scene pixels":
    let frame = ComposedFrame()
    let layers = frame.newContext()
    let reference = newSoftwareContext(workers = 1)
    for ctx in [BackendContext(layers), BackendContext(reference)]:
      ctx.begin()
      ctx.drawRect(rect(0, 0, 32, 64), color(1, 0, 0, 0.5))
      ctx.drawBackdropBlur(rect(10, 10, 40, 40), radii(), 4)
    let expected = reference.readPixels(rect(0, 0, 0, 0), false)
    check frame.image.data == expected.data
    check frame.image[10, 10].a == 128
    check frame.layers.len == 1

  test "source-image updates invalidate cached glyph and image layers":
    let frame = ComposedFrame()
    let ctx = frame.newContext()
    let image = newImage(4, 4)
    image.fill(rgba(255, 0, 0, 255))
    ctx.putImage(42.Hash, image)
    ctx.begin()
    ctx.drawImage(42.Hash, vec2(4), color(1, 1, 1, 1), false)
    let first = frame.layers[0]
    image.fill(rgba(0, 255, 0, 255))
    ctx.updateImage(42.Hash, image)
    ctx.begin()
    ctx.drawImage(42.Hash, vec2(4), color(1, 1, 1, 1), false)
    check frame.layers[0] != first
    check frame.image[4, 4].g == 255

  test "uncleared frames preserve previous compositor contents":
    let frame = ComposedFrame()
    let ctx = frame.newContext()
    ctx.begin()
    ctx.drawRect(rect(4, 4, 8, 8), color(1, 0, 0, 1))
    ctx.begin(clear = false)
    ctx.drawRect(rect(20, 20, 8, 8), color(0, 1, 0, 1))
    check frame.image[4, 4].r == 255
    check frame.image[20, 20].g == 255

  test "opacity groups composite overlaps once and retain nested transforms":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true)
    ctx.begin()
    ctx.beginOpacityGroup(0.5)
    ctx.drawRect(rect(2, 2, 16, 16), color(1, 0, 0, 1))
    ctx.drawRect(rect(10, 2, 16, 16), color(1, 0, 0, 1))
    ctx.saveTransform()
    ctx.translate(vec2(30, 0))
    ctx.beginOpacityGroup(0.5)
    ctx.drawRect(rect(0, 2, 8, 8), color(0, 0, 1, 1))
    ctx.endOpacityGroup()
    ctx.restoreTransform()
    ctx.endOpacityGroup()
    ctx.endFrame()
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[4, 4].a == image[12, 4].a
    check image[4, 4].a in 127'u8 .. 128'u8
    check image[32, 4].a in 63'u8 .. 64'u8

  test "inherited fractional mask clips overlapping group children once":
    let frame = ComposedFrame()
    let ctx = frame.newContext(native = true)
    proc render(overlap: bool): Image =
      ctx.begin()
      ctx.beginMask(rect(5.5, 5.5, 25, 25), radii())
      ctx.endMask()
      ctx.beginOpacityGroup(0.5)
      ctx.drawRect(rect(0, 0, 40, 40), color(1, 0, 0, 1))
      if overlap:
        ctx.drawRect(rect(0, 0, 40, 40), color(1, 0, 0, 1))
      ctx.endOpacityGroup()
      ctx.popMask()
      ctx.endFrame()
      ctx.readPixels(rect(0, 0, 0, 0), false)

    let single = render(false)
    let overlap = render(true)
    var fractional = false
    for y in 0 ..< 40:
      for x in 0 ..< 40:
        check single[x, y].a == overlap[x, y].a
        if single[x, y].a > 0 and single[x, y].a < 127:
          fractional = true
    check fractional
