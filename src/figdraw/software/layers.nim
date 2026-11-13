## Rasterize individual constructs with sdfy, then hand images to a compositor.
## The compositor and its window remain on the owning render thread.
import std/[hashes, math, tables, sets]
import pkg/[chroma, pixie, vmath]
import ../[commons, figbackend, fignodes]
import ./context

type
  ImageCacheStats* = object
    ## Hits/misses count visible layer draws in the current frame. Bytes and
    ## entries describe the retained cache, including packed compositor pixels.
    hits*, misses*: int
    bytes*, entries*: int
    nativeRects*: int ## Solid rectangles submitted without a raster image.

  LayerImage* = object
    ## Cached raster data borrowed by the compositor; treat it as immutable.
    image*: Image
    pixels*: seq[uint32] ## Optional packed premultiplied 0xAARRGGBB words.

  ImageComposer* = object
    ## Callbacks run synchronously on the render thread. `drawImage` borrows
    ## immutable cached data; copy it before retaining or modifying it.
    beginFrame*: proc(size: Vec2, clear: bool, color: Color) {.closure.}
    drawImage*: proc(layer: LayerImage, bounds: Rect) {.closure.}
    fillRect*: proc(bounds: Rect, fill: ColorRGBA): bool {.closure.}
      ## Optional native solid fill. Returning false must leave pixels unchanged.
    endFrame*: proc() {.closure.}
    snapshot*: proc(): Image {.closure.}
    coordinateScale*: float32 ## Raster pixels per compositor coordinate unit.
    frameScale*: proc(): float32 {.closure.}
    packedPixels*: bool
    background*: ColorRGBA

  RasterCommand = proc(raster: SoftwareContext) {.closure.}
  LayerMask = object
    bounds: Rect
    radii: CornerRadii2D[float32]
    transform: Mat3

  CachedLayer = object
    image: LayerImage
    used: uint64
    bytes: int

  CapturedLayer = object
    image: Image ## Nil for a native solid rectangle.
    bounds: Rect
    fill: ColorRGBA

  OpacityGroup = object
    image: Image
    opacity: float32
    maskCount: int
    inheritedMasks: seq[LayerMask]

  ImageLayerContext* = ref object of BackendContext
    raster: SoftwareContext
    composer: ImageComposer
    transform: Mat3
    transforms: seq[Mat3]
    masks: seq[LayerMask]
    cache: Table[Hash, CachedLayer]
    revisions: Table[Hash, uint64]
    sequence, useCounter: uint64
    frameSize: Vec2
    clearMain: bool
    clearColor: Color
    cacheBytes, cacheLimit: int
    frameHits, frameMisses, frameNativeRects: int
    captureKeys: HashSet[Hash]
    captureValid: bool
    captured: seq[CapturedLayer]
    opacityGroups: seq[OpacityGroup]

const LayerCacheBytes = 64 * 1024 * 1024

proc affine(m: Mat4): Mat3 =
  if m[0, 3] != 0 or m[1, 3] != 0 or m[2, 3] != 0 or m[3, 3] != 1:
    raise newException(ValueError, "Image layers support affine transforms")
  let origin = (m * vec3(0, 0, 1)).xy
  let x = (m * vec3(1, 0, 1)).xy - origin
  let y = (m * vec3(0, 1, 1)).xy - origin
  result = mat3()
  result[0, 0] = x.x
  result[0, 1] = x.y
  result[1, 0] = y.x
  result[1, 1] = y.y
  result[2, 0] = origin.x
  result[2, 1] = origin.y

proc apply(raster: SoftwareContext, m: Mat3) =
  var converted = mat4()
  converted[0, 0] = m[0, 0]
  converted[0, 1] = m[0, 1]
  converted[1, 0] = m[1, 0]
  converted[1, 1] = m[1, 1]
  converted[3, 0] = m[2, 0]
  converted[3, 1] = m[2, 1]
  raster.applyTransform(converted)

proc rasterBounds(ctx: ImageLayerContext, bounds: Rect): Rect =
  let corners = [
    bounds.xy,
    bounds.xy + vec2(bounds.w, 0),
    bounds.xy + bounds.wh,
    bounds.xy + vec2(0, bounds.h),
  ]
  var low = vec2(Inf.float32)
  var high = vec2(-Inf.float32)
  for corner in corners:
    let p = ctx.transform * corner
    low = min(low, p)
    high = max(high, p)
  let step = ctx.composer.coordinateScale
  low = max(vec2(0), floor(low / step) * step)
  high = min(ctx.frameSize, ceil(high / step) * step)
  rect(low.x, low.y, max(0'f32, high.x - low.x), max(0'f32, high.y - low.y))

proc configureRaster(ctx: ImageLayerContext, region: Rect) =
  ctx.raster.beginFrame(region.wh, true, color(0, 0, 0, 0))
  let maskStart =
    if ctx.opacityGroups.len > 0:
      ctx.opacityGroups[^1].maskCount
    else:
      0
  for i in maskStart ..< ctx.masks.len:
    let mask = ctx.masks[i]
    ctx.raster.saveTransform()
    ctx.raster.translate(-region.xy)
    ctx.raster.apply(mask.transform)
    ctx.raster.beginMask(mask.bounds, mask.radii)
    ctx.raster.endMask()
    ctx.raster.restoreTransform()
  ctx.raster.translate(-region.xy)
  ctx.raster.apply(ctx.transform)

proc snapshot(ctx: ImageLayerContext): Image =
  if ctx.frameSize.x <= 0 or ctx.frameSize.y <= 0:
    raise newException(ValueError, "Render a frame before capturing it")
  if not ctx.composer.snapshot.isNil:
    return ctx.composer.snapshot()
  if not ctx.clearMain:
    raise newException(
      ValueError, "Native uncleared-frame capture needs compositor readback"
    )
  if not ctx.captureValid:
    raise
      newException(ValueError, "Native frame exceeds the image capture cache budget")
  # Capture only on explicit request, using the immutable layers actually drawn.
  # Rendering never rebuilds or composites a native frame in software.
  result = newImage(ctx.frameSize.x.int, ctx.frameSize.y.int)
  let source = ctx.clearColor.rgba().rgbx()
  let background = ctx.composer.background.rgbx()
  let inverse = 255'u32 - source.a.uint32
  result.fill(
    rgbx(
      (source.r.uint32 + (background.r.uint32 * inverse + 127) div 255).uint8,
      (source.g.uint32 + (background.g.uint32 * inverse + 127) div 255).uint8,
      (source.b.uint32 + (background.b.uint32 * inverse + 127) div 255).uint8,
      (source.a.uint32 + (background.a.uint32 * inverse + 127) div 255).uint8,
    )
  )
  for layer in ctx.captured:
    if layer.image.isNil:
      let path = newPath()
      path.rect(layer.bounds)
      let paint = newPaint(SolidPaint)
      paint.color = layer.fill.color
      result.fillPath(path, paint)
    else:
      result.draw(layer.image, translate(layer.bounds.xy))

proc discardCapture(ctx: ImageLayerContext) =
  ctx.captureValid = false
  ctx.captured.setLen(0)
  ctx.captureKeys.clear()

proc present(ctx: ImageLayerContext, key: Hash, layer: LayerImage, region: Rect) =
  if ctx.opacityGroups.len > 0:
    ctx.opacityGroups[^1].image.draw(layer.image, translate(region.xy))
    return
  if ctx.composer.snapshot.isNil and ctx.clearMain and ctx.captureValid:
    if key notin ctx.cache or ctx.captured.len >= 32_768:
      ctx.discardCapture()
    else:
      ctx.captured.add(CapturedLayer(image: layer.image, bounds: region))
      ctx.captureKeys.incl(key)
  ctx.composer.drawImage(layer, region / ctx.composer.coordinateScale)

proc nativeRect(
    ctx: ImageLayerContext, bounds: Rect, fill: ColorRGBA, antialiased = false
): bool =
  if ctx.opacityGroups.len > 0 or ctx.composer.fillRect.isNil or ctx.masks.len != 0 or
      ctx.transform[0, 1] != 0 or ctx.transform[1, 0] != 0:
    return false
  if antialiased and (
    ctx.raster.sdfAaFactor() < 1 or abs(ctx.transform[0, 0]) != abs(ctx.transform[1, 1])
  ):
    return false
  if bounds.w <= 0 or bounds.h <= 0:
    return true
  let p0 = ctx.transform * bounds.xy
  let p1 = ctx.transform * (bounds.xy + bounds.wh)
  let low = max(vec2(0), min(p0, p1))
  let high = min(ctx.frameSize, max(p0, p1))
  if high.x <= low.x or high.y <= low.y:
    return true
  let nativeLow = low / ctx.composer.coordinateScale
  let nativeHigh = high / ctx.composer.coordinateScale
  if nativeLow != floor(nativeLow) or nativeHigh != floor(nativeHigh):
    return false
  let region = rect(low.x, low.y, high.x - low.x, high.y - low.y)
  if not ctx.composer.fillRect(region / ctx.composer.coordinateScale, fill):
    return false
  inc ctx.frameNativeRects
  if ctx.composer.snapshot.isNil and ctx.clearMain and ctx.captureValid:
    if ctx.captured.len >= 32_768:
      ctx.discardCapture()
    else:
      ctx.captured.add(CapturedLayer(bounds: region, fill: fill))
  true

proc trimCache(ctx: ImageLayerContext, needed: int) =
  while ctx.cache.len > 0 and
      (ctx.cacheBytes + needed > ctx.cacheLimit or ctx.cache.len >= 256):
    var oldest: Hash
    var age = uint64.high
    # Borrow entries: iterating by value deep-copies every packed pixel buffer.
    for key, entry in ctx.cache.mpairs:
      if entry.used < age:
        oldest = key
        age = entry.used
    if oldest in ctx.captureKeys:
      ctx.discardCapture()
    ctx.cacheBytes -= ctx.cache[oldest].bytes
    ctx.cache.del(oldest)

proc emit(ctx: ImageLayerContext, key: Hash, region: Rect, image: Image) =
  var layer = LayerImage(image: image)
  if ctx.composer.packedPixels:
    layer.pixels.setLen(image.data.len)
    for i, p in image.data:
      layer.pixels[i] =
        (p.a.uint32 shl 24) or (p.r.uint32 shl 16) or (p.g.uint32 shl 8) or p.b.uint32
  let bytes = image.data.len * (if ctx.composer.packedPixels: 8 else: 4)
  if bytes <= ctx.cacheLimit:
    ctx.trimCache(bytes)
    ctx.cache[key] = CachedLayer(image: layer, used: ctx.useCounter, bytes: bytes)
    ctx.cacheBytes += bytes
  ctx.present(key, layer, region)

proc drawLayer(ctx: ImageLayerContext, bounds: Rect, key: Hash, draw: RasterCommand) =
  let region = ctx.rasterBounds(bounds)
  if region.w <= 0 or region.h <= 0:
    return
  var placement = ctx.transform
  let origin = ctx.transform * bounds.xy - region.xy
  placement[2, 0] = origin.x
  placement[2, 1] = origin.y
  var maskKeys: seq[Hash]
  let maskStart =
    if ctx.opacityGroups.len > 0:
      ctx.opacityGroups[^1].maskCount
    else:
      0
  for i in maskStart ..< ctx.masks.len:
    let mask = ctx.masks[i]
    var transform = mask.transform
    let maskOrigin = mask.transform * mask.bounds.xy - region.xy
    transform[2, 0] = maskOrigin.x
    transform[2, 1] = maskOrigin.y
    maskKeys.add(hash((mask.bounds.wh, mask.radii, transform)))
  let completeKey =
    hash((key, region.wh, placement, maskKeys, ctx.raster.sdfAaFactor()))
  inc ctx.useCounter
  if completeKey in ctx.cache:
    inc ctx.frameHits
    ctx.cache[completeKey].used = ctx.useCounter
    ctx.present(completeKey, ctx.cache[completeKey].image, region)
    return
  inc ctx.frameMisses
  ctx.configureRaster(region)
  draw(ctx.raster)
  ctx.emit(completeKey, region, ctx.raster.readPixels(rect(0, 0, 0, 0), false))

method kind*(ctx: ImageLayerContext): RendererBackendKind =
  rbSoftware

method supportsAtlasUsage*(ctx: ImageLayerContext): bool =
  false

method entriesPtr*(ctx: ImageLayerContext): ptr Table[Hash, Rect] =
  ctx.raster.entriesPtr()

method atlasEntryMetaPtr*(ctx: ImageLayerContext): var Table[Hash, AtlasEntryMeta] =
  ctx.raster.atlasEntryMetaPtr()

method atlasSize*(ctx: ImageLayerContext): int =
  1

method pixelScale*(ctx: ImageLayerContext): float32 =
  1

method sdfAaFactor*(ctx: ImageLayerContext): float32 =
  ctx.raster.sdfAaFactor()

method setSdfAaFactor*(ctx: ImageLayerContext, value: float32) =
  ctx.raster.setSdfAaFactor(value)

method hasImage*(ctx: ImageLayerContext, key: Hash): bool =
  ctx.raster.hasImage(key)

method putImage*(ctx: ImageLayerContext, key: Hash, image: Image) =
  ctx.raster.putImage(key, image)
  inc ctx.sequence
  ctx.revisions[key] = ctx.sequence

method updateImage*(ctx: ImageLayerContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method addImage*(ctx: ImageLayerContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method putImage*(ctx: ImageLayerContext, image: ImgObj) =
  case image.kind
  of PixieImg:
    ctx.putImage(image.id.Hash, image.pimg)
  of CompressedImg:
    ctx.putCompressedImage(image.id.Hash, image.compressed)
  of FlippyImg:
    if image.flippy.mipmaps.len == 0:
      raise newException(ValueError, "Cannot cache an empty Flippy image")
    ctx.putImage(image.id.Hash, image.flippy.mipmaps[0])

method removeImage*(ctx: ImageLayerContext, id: ImageId) =
  procCall removeImage(BackendContext(ctx), id)
  ctx.raster.removeImage(id)
  ctx.revisions.del(id.Hash)

method clearImageAtlas*(ctx: ImageLayerContext) =
  ctx.raster.clearImageAtlas()
  ctx.cache.clear()
  ctx.discardCapture()
  ctx.cacheBytes = 0
  ctx.revisions.clear()
  ctx.noteAtlasRebuilt()

method resetImageAtlas*(ctx: ImageLayerContext, minimumSize: int) =
  ctx.clearImageAtlas()

method clearFontGlyphs*(ctx: ImageLayerContext, font: FontId) =
  ctx.raster.clearFontGlyphs(font)

method clearTypefaceGlyphs*(ctx: ImageLayerContext, face: TypefaceId) =
  ctx.raster.clearTypefaceGlyphs(face)

method beginFrame*(ctx: ImageLayerContext, size: Vec2, clear: bool, clearColor: Color) =
  if size.x <= 0 or size.y <= 0 or classify(size.x) in {fcNan, fcInf, fcNegInf} or
      classify(size.y) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "Frame dimensions must be positive")
  if ctx.opacityGroups.len != 0:
    raise newException(ValueError, "Unbalanced image-layer opacity groups")
  ctx.frameSize = vec2(ceil(size.x), ceil(size.y))
  if not ctx.composer.frameScale.isNil:
    ctx.composer.coordinateScale = ctx.composer.frameScale()
  if ctx.composer.coordinateScale <= 0 or
      classify(ctx.composer.coordinateScale) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "Compositor scale must be finite and positive")
  ctx.clearMain = clear
  ctx.clearColor = clearColor
  ctx.frameHits = 0
  ctx.frameMisses = 0
  ctx.frameNativeRects = 0
  ctx.transform = mat3()
  ctx.transforms.setLen(0)
  ctx.masks.setLen(0)
  ctx.captured.setLen(0)
  ctx.captureKeys.clear()
  ctx.captureValid = clear
  ctx.composer.beginFrame(ctx.frameSize, clear, clearColor)

method endFrame*(ctx: ImageLayerContext) =
  if ctx.opacityGroups.len != 0:
    raise newException(ValueError, "Unbalanced image-layer opacity groups")
  if not ctx.composer.endFrame.isNil:
    ctx.composer.endFrame()

method beginOpacityGroup*(ctx: ImageLayerContext, opacity: float32) =
  let maskStart =
    if ctx.opacityGroups.len > 0:
      ctx.opacityGroups[^1].maskCount
    else:
      0
  ctx.opacityGroups.add(
    OpacityGroup(
      image: newImage(ctx.frameSize.x.int, ctx.frameSize.y.int),
      opacity: clamp(opacity, 0.0'f32, 1.0'f32),
      maskCount: ctx.masks.len,
      inheritedMasks: ctx.masks[maskStart ..< ctx.masks.len],
    )
  )

method endOpacityGroup*(ctx: ImageLayerContext) =
  if ctx.opacityGroups.len == 0:
    raise newException(ValueError, "Unbalanced image-layer opacity groups")
  let group = ctx.opacityGroups.pop()
  if group.inheritedMasks.len > 0:
    ctx.raster.beginFrame(ctx.frameSize, true, color(0, 0, 0, 0))
    for mask in group.inheritedMasks:
      ctx.raster.saveTransform()
      ctx.raster.apply(mask.transform)
      ctx.raster.beginMask(mask.bounds, mask.radii)
      ctx.raster.endMask()
      ctx.raster.restoreTransform()
    ctx.raster.drawRect(rect(0, 0, ctx.frameSize.x, ctx.frameSize.y), color(1, 1, 1, 1))
    let mask = ctx.raster.readPixels(rect(0, 0, 0, 0), false)
    for i, pixel in group.image.data.mpairs:
      let alpha = mask.data[i].a.uint32
      pixel.r = ((pixel.r.uint32 * alpha + 127) div 255).uint8
      pixel.g = ((pixel.g.uint32 * alpha + 127) div 255).uint8
      pixel.b = ((pixel.b.uint32 * alpha + 127) div 255).uint8
      pixel.a = ((pixel.a.uint32 * alpha + 127) div 255).uint8
  for pixel in group.image.data.mitems:
    pixel.r = (pixel.r.float32 * group.opacity + 0.5'f32).uint8
    pixel.g = (pixel.g.float32 * group.opacity + 0.5'f32).uint8
    pixel.b = (pixel.b.float32 * group.opacity + 0.5'f32).uint8
    pixel.a = (pixel.a.float32 * group.opacity + 0.5'f32).uint8
  if ctx.opacityGroups.len > 0:
    ctx.opacityGroups[^1].image.draw(group.image)
  else:
    var layer = LayerImage(image: group.image)
    if ctx.composer.packedPixels:
      layer.pixels.setLen(group.image.data.len)
      for i, p in group.image.data:
        layer.pixels[i] =
          (p.a.uint32 shl 24) or (p.r.uint32 shl 16) or (p.g.uint32 shl 8) or p.b.uint32
    let region = rect(0, 0, ctx.frameSize.x, ctx.frameSize.y)
    if ctx.composer.snapshot.isNil and ctx.clearMain and ctx.captureValid:
      if ctx.captured.len >= 32_768:
        ctx.discardCapture()
      else:
        ctx.captured.add(CapturedLayer(image: group.image, bounds: region))
    ctx.composer.drawImage(layer, region / ctx.composer.coordinateScale)

method translate*(ctx: ImageLayerContext, v: Vec2) =
  ctx.transform = ctx.transform * translate(v)

method rotate*(ctx: ImageLayerContext, angle: float32) =
  ctx.transform = ctx.transform * rotate(angle)

method scale*(ctx: ImageLayerContext, scale: Vec2) =
  ctx.transform = ctx.transform * scale(scale)

method scale*(ctx: ImageLayerContext, scale: float32) =
  ctx.scale(vec2(scale))

method saveTransform*(ctx: ImageLayerContext) =
  ctx.transforms.add(ctx.transform)

method restoreTransform*(ctx: ImageLayerContext) =
  if ctx.transforms.len == 0:
    raise newException(ValueError, "Unbalanced image-layer transform stack")
  ctx.transform = ctx.transforms.pop()

method applyTransform*(ctx: ImageLayerContext, m: Mat4) =
  ctx.transform = ctx.transform * affine(m)

method beginMask*(ctx: ImageLayerContext, bounds: Rect, radii: CornerRadii2D[float32]) =
  ctx.masks.add LayerMask(bounds: bounds, radii: radii, transform: ctx.transform)

method endMask*(ctx: ImageLayerContext) =
  discard

method popMask*(ctx: ImageLayerContext) =
  if ctx.masks.len == 0:
    raise newException(ValueError, "Unbalanced image-layer mask stack")
  ctx.masks.setLen(ctx.masks.len - 1)

method drawRect*(ctx: ImageLayerContext, bounds: Rect, fill: Color) =
  if ctx.nativeRect(bounds, fill.rgba()):
    return
  ctx.drawLayer(
    bounds,
    hash(("rect", bounds.wh, fill)),
    proc(r: SoftwareContext) =
      r.drawRect(bounds, fill),
  )

method drawRoundedRectSdf*(
    ctx: ImageLayerContext,
    bounds: Rect,
    fill: BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor, spread: float32,
    shapeSize: Vec2,
) =
  if mode == sdfModeClipAA and fill.kind == bfColor and
      radii == default(CornerRadii2D[float32]) and
      ctx.nativeRect(bounds, fill.color, antialiased = true):
    return
  ctx.drawLayer(
    bounds,
    hash(("rounded", bounds.wh, fill, radii, mode, factor, spread, shapeSize)),
    proc(r: SoftwareContext) =
      r.drawRoundedRectSdf(bounds, fill, radii, mode, factor, spread, shapeSize),
  )

method drawRoundedRectSdf*(
    ctx: ImageLayerContext,
    bounds: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor, spread: float32,
    shapeSize: Vec2,
) =
  if mode == sdfModeClipAA and radii == default(CornerRadii2D[float32]) and
      colors[0] == colors[1] and colors[0] == colors[2] and colors[0] == colors[3] and
      ctx.nativeRect(bounds, colors[0], antialiased = true):
    return
  ctx.drawLayer(
    bounds,
    hash(("roundedColors", bounds.wh, colors, radii, mode, factor, spread, shapeSize)),
    proc(r: SoftwareContext) =
      r.drawRoundedRectSdf(bounds, colors, radii, mode, factor, spread, shapeSize),
  )

method drawImage*(
    ctx: ImageLayerContext,
    key: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  let rect = ctx.raster.entriesPtr()[][key]
  let size = if size == vec2(0): rect.wh else: size
  ctx.drawLayer(
    rect(pos.x, pos.y, size.x, size.y),
    hash(("image", key, ctx.revisions.getOrDefault(key), colors, size, flipY)),
    proc(r: SoftwareContext) =
      r.drawImage(key, pos, colors, size, flipY),
  )

method drawImageAdj*(
    ctx: ImageLayerContext, key: Hash, pos: Vec2, color: Color, size: Vec2
) =
  ctx.drawImage(key, pos, color, size, false)

method drawFilledQuad*(
    ctx: ImageLayerContext, vertices: array[4, Vec2], colors: array[4, ColorRGBA]
) =
  var low = vertices[0]
  var high = vertices[0]
  for vertex in vertices:
    low = min(low, vertex)
    high = max(high, vertex)
  ctx.drawLayer(
    rect(low.x, low.y, high.x - low.x, high.y - low.y),
    hash(
      (
        "quad",
        [vertices[0] - low, vertices[1] - low, vertices[2] - low, vertices[3] - low],
        colors,
      )
    ),
    proc(r: SoftwareContext) =
      r.drawFilledQuad(vertices, colors),
  )

method drawQuadraticBezierSdf*(
    ctx: ImageLayerContext,
    bounds: Rect,
    fill: BackendFill,
    p0, p1, p2: Vec2,
    weight: float32,
    cap: StrokeCap,
) =
  ctx.drawLayer(
    bounds,
    hash(("bezier", bounds.wh, fill, p0, p1, p2, weight, cap)),
    proc(r: SoftwareContext) =
      r.drawQuadraticBezierSdf(bounds, fill, p0, p1, p2, weight, cap),
  )

method drawMsdfImage*(
    ctx: ImageLayerContext,
    key: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange, threshold, weight: float32,
    flipY: bool,
) =
  ctx.drawLayer(
    rect(pos.x, pos.y, size.x, size.y),
    hash(
      (
        "msdf",
        key,
        ctx.revisions.getOrDefault(key),
        color,
        size,
        pxRange,
        threshold,
        weight,
        flipY,
      )
    ),
    proc(r: SoftwareContext) =
      r.drawMsdfImage(key, pos, color, size, pxRange, threshold, weight, flipY),
  )

method drawMtsdfImage*(
    ctx: ImageLayerContext,
    key: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange, threshold, weight: float32,
    flipY: bool,
) =
  ctx.drawLayer(
    rect(pos.x, pos.y, size.x, size.y),
    hash(
      (
        "mtsdf",
        key,
        ctx.revisions.getOrDefault(key),
        color,
        size,
        pxRange,
        threshold,
        weight,
        flipY,
      )
    ),
    proc(r: SoftwareContext) =
      r.drawMtsdfImage(key, pos, color, size, pxRange, threshold, weight, flipY),
  )

method drawBackdropBlur*(
    ctx: ImageLayerContext,
    bounds: Rect,
    radii: CornerRadii2D[float32],
    blurRadius: float32,
) =
  ## Native/Pixie image composition does not require backdrop readback.
  ## The scene renderer preserves the node's overlay geometry.
  discard

method readPixels*(ctx: ImageLayerContext, frame: Rect, readFront: bool): Image =
  let image = ctx.snapshot()
  if frame.w <= 0 or frame.h <= 0:
    return image
  let x = max(0, floor(frame.x).int)
  let y = max(0, floor(frame.y).int)
  let right = min(image.width, ceil(frame.x + frame.w).int)
  let bottom = min(image.height, ceil(frame.y + frame.h).int)
  if right <= x or bottom <= y:
    raise newException(ValueError, "Capture rectangle is outside the frame")
  image.subImage(x, y, right - x, bottom - y)

func imageCacheStats*(ctx: ImageLayerContext): ImageCacheStats =
  ## Query on the render thread after rendering a frame.
  ImageCacheStats(
    hits: ctx.frameHits,
    misses: ctx.frameMisses,
    bytes: ctx.cacheBytes,
    entries: ctx.cache.len,
    nativeRects: ctx.frameNativeRects,
  )

proc newImageLayerContext*(
    composer: ImageComposer,
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
    maxCacheBytes: Positive = LayerCacheBytes,
): ImageLayerContext =
  ## Rasterize bounded images using sdfy and reuse up to `maxCacheBytes` of
  ## cached pixels. The compositor owns final blending and presentation.
  ## Native capture requires a cleared frame whose layers remain cached;
  ## a compositor `snapshot` callback can provide its own readback instead.
  if composer.beginFrame.isNil or composer.drawImage.isNil or
      composer.coordinateScale <= 0 or
      classify(composer.coordinateScale) in {fcNan, fcInf, fcNegInf}:
    raise newException(
      ValueError, "Image compositor needs frame/draw callbacks and a positive scale"
    )
  result = ImageLayerContext(
    composer: composer,
    transform: mat3(),
    cacheLimit: maxCacheBytes,
    raster: newSoftwareContext(
      workers = workers, parallelThreshold = parallelThreshold, subscribeImages = false
    ),
  )
  result.ensureImageMessageSubscription()
