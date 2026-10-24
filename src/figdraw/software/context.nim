## CPU rendering into Pixie images using sdfy's distance fields.
##
## Pass this context to `newFigRenderer` to keep the regular scene, glyph and
## image APIs. No window or GPU context is needed. Contexts and their images
## belong to the rendering thread; captures return independent images.

import std/[hashes, math, tables]
import pkg/[chroma, pixie, vmath]
import pkg/sdfy/shapes
import pkg/sdfy/spans except distances
from pkg/sdfy/sdfytypes import MsdfBitmapParams
import ../[commons, figbackend, fignodes]
import ./distances
import ./raster

export ThreadedSdfyEnabled

type
  FramePresenter* = proc(image: Image) {.closure.}
    ## Called synchronously at endFrame. The image is borrowed until return.
  SoftwareContext* = ref object of BackendContext
    backing: Image
    transform: Mat3
    transforms: seq[Mat3]
    mask: Image
    masks: seq[Image]
    images: Table[Hash, Image]
    entries: Table[Hash, Rect]
    metadata: Table[Hash, AtlasEntryMeta]
    pixelScaleValue, aaFactor: float32
    presenter: FramePresenter
    rasterWorkers: RasterWorkers

  PixelSampler = proc(p: Vec2, aaWidth: float32): ColorRGBX {.closure.}
  PixelBatchSampler =
    proc(points: array[4, Vec2], aaWidth: float32): array[4, ColorRGBX] {.closure.}
  SdfyRasterFactory = proc(inverse: Mat3, aaWidth: float32): SdfyRaster {.closure.}

func coverage(distance, aaWidth: float32): float32 =
  clamp(0.5'f32 - distance / max(aaWidth, 0.00001'f32), 0'f32, 1'f32)

func withCoverage(color: ColorRGBA, alpha: float32): ColorRGBX =
  var color = color
  color.a = round(color.a.float32 * clamp(alpha, 0'f32, 1'f32)).uint8
  color.rgbx()

func over(src, dst: ColorRGBX, mask = 255'u8): ColorRGBX =
  let
    r = (src.r.uint32 * mask.uint32 + 127) div 255
    g = (src.g.uint32 * mask.uint32 + 127) div 255
    b = (src.b.uint32 * mask.uint32 + 127) div 255
    a = (src.a.uint32 * mask.uint32 + 127) div 255
    inv = 255'u32 - a
  ColorRGBX(
    r: (r + (dst.r.uint32 * inv + 127) div 255).uint8,
    g: (g + (dst.g.uint32 * inv + 127) div 255).uint8,
    b: (b + (dst.b.uint32 * inv + 127) div 255).uint8,
    a: (a + (dst.a.uint32 * inv + 127) div 255).uint8,
  )

func mixPixel(a, b: ColorRGBX, alpha: uint8): ColorRGBX =
  let t = alpha.uint32
  let inv = 255'u32 - t
  ColorRGBX(
    r: ((a.r.uint32 * t + b.r.uint32 * inv + 127) div 255).uint8,
    g: ((a.g.uint32 * t + b.g.uint32 * inv + 127) div 255).uint8,
    b: ((a.b.uint32 * t + b.b.uint32 * inv + 127) div 255).uint8,
    a: ((a.a.uint32 * t + b.a.uint32 * inv + 127) div 255).uint8,
  )

func mixColor(a, b: ColorRGBA, t: float32): ColorRGBA =
  let t = clamp(t, 0'f32, 1'f32)
  rgba(
    round(a.r.float32 * (1 - t) + b.r.float32 * t).uint8,
    round(a.g.float32 * (1 - t) + b.g.float32 * t).uint8,
    round(a.b.float32 * (1 - t) + b.b.float32 * t).uint8,
    round(a.a.float32 * (1 - t) + b.a.float32 * t).uint8,
  )

func sampleColors(colors: array[4, ColorRGBA], uv: Vec2): ColorRGBA =
  ## Backend vertex order is bottom-left, bottom-right, top-right, top-left.
  mixColor(
    mixColor(colors[3], colors[2], uv.x), mixColor(colors[0], colors[1], uv.x), uv.y
  )

func sampleFill(fill: BackendFill, uv: Vec2): ColorRGBA =
  let axis =
    case fill.kind
    of bfColor: fgaX
    of bfLinear2: fill.lin2Axis
    of bfLinear3: fill.lin3Axis
  let t =
    case axis
    of fgaX:
      uv.x
    of fgaY:
      uv.y
    of fgaDiagTLBR:
      (uv.x + uv.y) * 0.5'f32
    of fgaDiagBLTR:
      (uv.x + 1'f32 - uv.y) * 0.5'f32
  fill.sampleColor(t)

func cornerVector(radii: array[DirectionCorners, float32]): Vec4 =
  vec4(radii[dcBottomRight], radii[dcTopRight], radii[dcBottomLeft], radii[dcTopLeft])

proc roundedField(halfSize: Vec2, radii: CornerRadii2D[float32]): RoundedBoxField =
  roundedBoxField(halfSize, cornerVector(radii.x), cornerVector(radii.y))

proc composite(
    ctx: SoftwareContext, image: Image, x, y: int, src: ColorRGBX, replace: bool
) {.inline.} =
  let alpha =
    if ctx.mask.isNil:
      255'u8
    else:
      ctx.mask[x, y].a
  image[x, y] =
    if replace:
      mixPixel(src, image[x, y], alpha)
    else:
      over(src, image[x, y], alpha)

func contains(bounds: Rect, p: Vec2): bool {.inline.} =
  p.x >= bounds.x and p.y >= bounds.y and p.x < bounds.x + bounds.w and
    p.y < bounds.y + bounds.h

proc rasterize(
    ctx: SoftwareContext,
    bounds: Rect,
    sample: PixelSampler = nil,
    target: Image = nil,
    replace = false,
    sampleBatch: PixelBatchSampler = nil,
    sampleRaster: SdfyRasterFactory = nil,
) =
  if ctx.backing.isNil or bounds.w <= 0 or bounds.h <= 0:
    return
  let
    mat = ctx.transform
    determinant = mat[0, 0] * mat[1, 1] - mat[0, 1] * mat[1, 0]
  if abs(determinant) < 0.000001'f32:
    return
  let
    inverse = mat.inverse()
    aaWidth =
      max(
        length(inverse * vec2(1, 0) - inverse * vec2(0, 0)),
        length(inverse * vec2(0, 1) - inverse * vec2(0, 0)),
      ) / ctx.aaFactor
    corners = [
      mat * bounds.xy,
      mat * (bounds.xy + vec2(bounds.w, 0)),
      mat * (bounds.xy + bounds.wh),
      mat * (bounds.xy + vec2(0, bounds.h)),
    ]
    image = if target.isNil: ctx.backing else: target
  var low = corners[0]
  var high = corners[0]
  for p in corners:
    low = min(low, p)
    high = max(high, p)
  let
    x0 = max(0, floor(low.x).int)
    y0 = max(0, floor(low.y).int)
    x1 = min(image.width, ceil(high.x).int)
    y1 = min(image.height, ceil(high.y).int)
  if x1 <= x0 or y1 <= y0:
    return
  if not sampleRaster.isNil:
    ctx.rasterWorkers.renderSdfy(
      sampleRaster(inverse, aaWidth), image, ctx.mask, x0, y0, x1, y1
    )
    return
  for y in y0 ..< y1:
    var x = x0
    when softwareSimdEnabled:
      if not sampleBatch.isNil:
        while x + 4 <= x1:
          var points: array[4, Vec2]
          for lane in 0 ..< 4:
            points[lane] =
              inverse * vec2((x + lane).float32 + 0.5'f32, y.float32 + 0.5'f32)
          let pixels = sampleBatch(points, aaWidth)
          for lane in 0 ..< 4:
            if bounds.contains(points[lane]):
              ctx.composite(image, x + lane, y, pixels[lane], replace)
          x += 4
    while x < x1:
      let p = inverse * vec2(x.float32 + 0.5'f32, y.float32 + 0.5'f32)
      if bounds.contains(p):
        ctx.composite(image, x, y, sample(p, aaWidth), replace)
      inc x

method kind*(ctx: SoftwareContext): RendererBackendKind =
  rbSoftware

method supportsAtlasUsage*(ctx: SoftwareContext): bool =
  false

method entriesPtr*(ctx: SoftwareContext): ptr Table[Hash, Rect] =
  addr ctx.entries

method atlasEntryMetaPtr*(ctx: SoftwareContext): var Table[Hash, AtlasEntryMeta] =
  ctx.metadata

method atlasSize*(ctx: SoftwareContext): int =
  1

method pixelScale*(ctx: SoftwareContext): float32 =
  ctx.pixelScaleValue

method sdfAaFactor*(ctx: SoftwareContext): float32 =
  ctx.aaFactor

method setSdfAaFactor*(ctx: SoftwareContext, aaFactor: float32) =
  ctx.aaFactor = max(aaFactor, 0.0001'f32)

method hasImage*(ctx: SoftwareContext, key: Hash): bool =
  key in ctx.images

method putImage*(ctx: SoftwareContext, path: Hash, image: Image) =
  if image.isNil:
    raise newException(ValueError, "Cannot cache a nil image")
  ctx.images[path] = image.copy()
  # Atlas size is one, so these dimensions also serve normalized lookups.
  ctx.entries[path] = rect(0, 0, image.width.float32, image.height.float32)

method updateImage*(ctx: SoftwareContext, path: Hash, image: Image) =
  ctx.putImage(path, image)

method addImage*(ctx: SoftwareContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method putImage*(ctx: SoftwareContext, image: ImgObj) =
  case image.kind
  of PixieImg:
    ctx.putImage(image.id.Hash, image.pimg)
  of FlippyImg:
    if image.flippy.mipmaps.len == 0:
      raise newException(ValueError, "Cannot cache an empty Flippy image")
    ctx.putImage(image.id.Hash, image.flippy.mipmaps[0])

method removeImage*(ctx: SoftwareContext, id: ImageId) =
  procCall removeImage(BackendContext(ctx), id)
  if id.Hash notin ctx.entries:
    ctx.images.del(id.Hash)

method clearImageAtlas*(ctx: SoftwareContext) =
  ctx.images.clear()
  ctx.entries.clear()
  ctx.metadata.clear()
  ctx.noteAtlasRebuilt()

method resetImageAtlas*(ctx: SoftwareContext, minimumSize: int) =
  ctx.clearImageAtlas()

proc evictUnusedImages(ctx: SoftwareContext) =
  var unused: seq[Hash]
  for key in ctx.images.keys:
    if key notin ctx.entries:
      unused.add(key)
  for key in unused:
    ctx.images.del(key)

method clearFontGlyphs*(ctx: SoftwareContext, fontId: FontId) =
  procCall clearFontGlyphs(BackendContext(ctx), fontId)
  ctx.evictUnusedImages()

method clearTypefaceGlyphs*(ctx: SoftwareContext, typefaceId: TypefaceId) =
  procCall clearTypefaceGlyphs(BackendContext(ctx), typefaceId)
  ctx.evictUnusedImages()

method beginFrame*(
    ctx: SoftwareContext, frameSize: Vec2, clearMain: bool, clearMainColor: Color
) =
  let
    width = ceil(frameSize.x * ctx.pixelScaleValue).int
    height = ceil(frameSize.y * ctx.pixelScaleValue).int
  if width <= 0 or height <= 0:
    raise newException(ValueError, "Software frame dimensions must be positive")
  if ctx.backing.isNil or ctx.backing.width != width or ctx.backing.height != height:
    ctx.backing = newImage(width, height)
  ctx.transform = mat3()
  ctx.transforms.setLen(0)
  ctx.mask = nil
  ctx.masks.setLen(0)
  if clearMain:
    ctx.backing.fill(clearMainColor)

method endFrame*(ctx: SoftwareContext) =
  if not ctx.presenter.isNil:
    ctx.presenter(ctx.backing)

method translate*(ctx: SoftwareContext, v: Vec2) =
  ctx.transform = ctx.transform * translate(v)

method rotate*(ctx: SoftwareContext, angle: float32) =
  ctx.transform = ctx.transform * rotate(angle)

method scale*(ctx: SoftwareContext, s: Vec2) =
  ctx.transform = ctx.transform * scale(s)

method scale*(ctx: SoftwareContext, s: float32) =
  ctx.scale(vec2(s, s))

method saveTransform*(ctx: SoftwareContext) =
  ctx.transforms.add(ctx.transform)

method restoreTransform*(ctx: SoftwareContext) =
  if ctx.transforms.len == 0:
    raise newException(ValueError, "Unbalanced software transform stack")
  ctx.transform = ctx.transforms.pop()

method applyTransform*(ctx: SoftwareContext, m: Mat4) =
  if m[0, 3] != 0 or m[1, 3] != 0 or m[2, 3] != 0 or m[3, 3] != 1:
    raise newException(ValueError, "Software rendering supports affine transforms")
  let
    origin = (m * vec3(0, 0, 1)).xy
    xAxis = (m * vec3(1, 0, 1)).xy - origin
    yAxis = (m * vec3(0, 1, 1)).xy - origin
  var affine = mat3()
  affine[0, 0] = xAxis.x
  affine[0, 1] = xAxis.y
  affine[1, 0] = yAxis.x
  affine[1, 1] = yAxis.y
  affine[2, 0] = origin.x
  affine[2, 1] = origin.y
  ctx.transform = ctx.transform * affine

method readPixels*(ctx: SoftwareContext, frame: Rect, readFront: bool): Image =
  if ctx.backing.isNil:
    raise newException(ValueError, "Render a software frame before capturing it")
  if frame.w <= 0 or frame.h <= 0:
    return ctx.backing.copy()
  let
    x = max(0, floor(frame.x).int)
    y = max(0, floor(frame.y).int)
    right = min(ctx.backing.width, ceil(frame.x + frame.w).int)
    bottom = min(ctx.backing.height, ceil(frame.y + frame.h).int)
  if right <= x or bottom <= y:
    raise newException(ValueError, "Capture rectangle is outside the software frame")
  ctx.backing.subImage(x, y, right - x, bottom - y)

proc newSoftwareContext*(
    pixelScale = 1'f32,
    presenter: FramePresenter = nil,
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): SoftwareContext =
  ## Creates a CPU renderer. An optional presenter receives each finished image.
  ## Large rounded draws use an internal lazy Sigils pool and wait before returning.
  ## workers=0 selects up to four CPUs; workers=1 forces inline rendering.
  ## Small draws stay inline. Runtime pools are shared and stop at process exit.
  if pixelScale <= 0 or classify(pixelScale) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "pixelScale must be finite and positive")
  result = SoftwareContext(
    transform: mat3(),
    pixelScaleValue: pixelScale,
    aaFactor: DefaultSdfAaFactor,
    presenter: presenter,
    rasterWorkers: initRasterWorkers(workers, parallelThreshold),
  )
  result.ensureImageMessageSubscription()

method drawRect*(ctx: SoftwareContext, rect: Rect, color: Color) =
  ctx.rasterize(
    rect,
    proc(p: Vec2, aa: float32): ColorRGBX =
      color.rgbx(),
  )

proc spanPaint(fill: BackendFill, bounds: Rect): SpanPaint =
  if fill.kind == bfColor or bounds.w <= 0 or bounds.h <= 0:
    return initSolidPaint(fill.sampleColor(0))
  let gradientAxis = if fill.kind == bfLinear2: fill.lin2Axis else: fill.lin3Axis
  var origin = bounds.xy
  let axis =
    case gradientAxis
    of fgaX:
      vec2(bounds.w, 0)
    of fgaY:
      vec2(0, bounds.h)
    of fgaDiagTLBR, fgaDiagBLTR:
      let direction = vec2(
        0.5'f32 / bounds.w,
        (if gradientAxis == fgaDiagTLBR: 0.5'f32 else: -0.5'f32) / bounds.h,
      )
      if gradientAxis == fgaDiagBLTR:
        origin.y += bounds.h
      direction / dot(direction, direction)
  if fill.kind == bfLinear2:
    initLinearPaint(fill.lin2Start, fill.lin2Stop, origin, axis)
  else:
    initLinearPaint(
      fill.lin3Start, fill.lin3Mid, fill.lin3Stop, origin, axis, fill.lin3MidPos
    )

proc drawRounded(
    ctx: SoftwareContext,
    rect: Rect,
    paint: SpanPaint,
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor, spread: float32,
    shapeSize: Vec2,
) =
  let spanMode =
    case mode
    of sdfModeClipAA:
      smFill
    of sdfModeAnnular:
      smStroke
    of sdfModeAnnularAA:
      smStrokeAA
    of sdfModeDropShadow, sdfModeDropShadowAA:
      smDropShadow
    of sdfModeInsetShadow, sdfModeInsetShadowAnnular:
      smInsetShadow
    else:
      raise newException(ValueError, "Unsupported rounded rectangle SDF mode: " & $mode)
  if rect.w <= 0 or rect.h <= 0:
    return
  let
    center = rect.xy + rect.wh * 0.5'f32
    halfSize =
      if spanMode == smDropShadow and shapeSize.x > 0 and shapeSize.y > 0:
        shapeSize * 0.5'f32
      else:
        rect.wh * 0.5'f32
    field = initRoundedBoxField(
      halfSize, cornerVector(radii.x), cornerVector(radii.y), center
    )
    clip = initSpanClip(rect.xy, rect.xy + rect.wh)
  ctx.rasterize(
    rect,
    sampleRaster = proc(inverse: Mat3, aa: float32): SdfyRaster =
      SdfyRaster(
        field: field,
        paint: paint,
        clip: clip,
        transform: inverse,
        useSimd: softwareSimdEnabled,
        effect: initSpanEffect(
          spanMode,
          aaWidth = aa,
          strokeWidth = max(factor, 0'f32),
          blurRadius = max(factor, 0'f32),
          spread = spread,
          insetOffset = shapeSize,
        ),
      ),
  )

method drawRoundedRectSdf*(
    ctx: SoftwareContext,
    rect: Rect,
    fill: BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor, spread: float32,
    shapeSize: Vec2,
) =
  ctx.drawRounded(rect, spanPaint(fill, rect), radii, mode, factor, spread, shapeSize)

method drawRoundedRectSdf*(
    ctx: SoftwareContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor, spread: float32,
    shapeSize: Vec2,
) =
  let paint =
    if rect.w > 0 and rect.h > 0:
      initBilinearPaint([colors[3], colors[2], colors[1], colors[0]], rect.xy, rect.wh)
    else:
      initSolidPaint(colors[0])
  ctx.drawRounded(rect, paint, radii, mode, factor, spread, shapeSize)

method beginMask*(ctx: SoftwareContext, clipRect: Rect, radii: CornerRadii2D[float32]) =
  let
    mask = newImage(ctx.backing.width, ctx.backing.height)
    center = clipRect.xy + clipRect.wh * 0.5'f32
    field = initRoundedBoxField(
      clipRect.wh * 0.5'f32, cornerVector(radii.x), cornerVector(radii.y), center
    )
    clip = initSpanClip(clipRect.xy, clipRect.xy + max(clipRect.wh, vec2(0)))
    paint = initSolidPaint(rgba(255, 255, 255, 255))
  ctx.rasterize(
    clipRect,
    target = mask,
    sampleRaster = proc(inverse: Mat3, aa: float32): SdfyRaster =
      SdfyRaster(
        field: field,
        paint: paint,
        clip: clip,
        transform: inverse,
        effect: initSpanEffect(aaWidth = aa),
        useSimd: softwareSimdEnabled,
      ),
  )
  ctx.masks.add(ctx.mask)
  ctx.mask = mask

method endMask*(ctx: SoftwareContext) =
  discard

method popMask*(ctx: SoftwareContext) =
  if ctx.masks.len == 0:
    raise newException(ValueError, "Unbalanced software clip stack")
  ctx.mask = ctx.masks.pop()

method drawImage*(
    ctx: SoftwareContext,
    path: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  if path notin ctx.entries or path notin ctx.images:
    raise newException(KeyError, "Software image is not cached: " & $path)
  let
    image = ctx.images[path]
    size =
      if size.x == 0 and size.y == 0:
        vec2(image.width.float32, image.height.float32)
      else:
        size
  ctx.rasterize(
    rect(pos.x, pos.y, size.x, size.y),
    proc(p: Vec2, aa: float32): ColorRGBX =
      let uv = (p - pos) / size
      let y =
        if flipY:
          1'f32 - uv.y
        else:
          uv.y
      let pixel = image.getRgbaSmooth(
        clamp(uv.x * image.width.float32 - 0.5'f32, 0'f32, (image.width - 1).float32),
        clamp(y * image.height.float32 - 0.5'f32, 0'f32, (image.height - 1).float32),
      )
      let tint = sampleColors(colors, uv)
      ColorRGBX(
        r: ((pixel.r.uint32 * tint.r.uint32 * tint.a.uint32 + 32512) div 65025).uint8,
        g: ((pixel.g.uint32 * tint.g.uint32 * tint.a.uint32 + 32512) div 65025).uint8,
        b: ((pixel.b.uint32 * tint.b.uint32 * tint.a.uint32 + 32512) div 65025).uint8,
        a: ((pixel.a.uint32 * tint.a.uint32 + 127) div 255).uint8,
      ),
  )

method drawImageAdj*(
    ctx: SoftwareContext, path: Hash, pos: Vec2, color: Color, size: Vec2
) =
  ctx.drawImage(path, pos, color, size, false)

func cross(a, b: Vec2): float32 =
  a.x * b.y - a.y * b.x

method drawFilledQuad*(
    ctx: SoftwareContext, verts: array[4, Vec2], colors: array[4, ColorRGBA]
) =
  var low = verts[0]
  var high = verts[0]
  for p in verts:
    low = min(low, p)
    high = max(high, p)
  let
    size = high - low
    orientation =
      if cross(verts[1] - verts[0], verts[2] - verts[1]) >= 0: 1'f32 else: -1'f32
  ctx.rasterize(
    rect(low.x, low.y, size.x, size.y),
    proc(p: Vec2, aa: float32): ColorRGBX =
      var distance = -Inf.float32
      for i in 0 ..< 4:
        let edge = verts[(i + 1) mod 4] - verts[i]
        if length(edge) > 0:
          distance =
            max(distance, -orientation * cross(edge, p - verts[i]) / length(edge))
      withCoverage(sampleColors(colors, (p - low) / size), coverage(distance, aa)),
  )

method drawQuadraticBezierSdf*(
    ctx: SoftwareContext,
    rect: Rect,
    fill: BackendFill,
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
) =
  # Backend control points are relative to the bounding rectangle's center.
  let center = rect.xy + rect.wh * 0.5'f32
  ctx.rasterize(
    rect,
    proc(p: Vec2, aa: float32): ColorRGBX =
      let p = p - center
      let bend = p0 - p1 * 2'f32 + p2
      var distance: float32
      if dot(bend, bend) < 0.000001'f32:
        let line = p2 - p0
        let t =
          clamp(dot(p - p0, line) / max(dot(line, line), 0.000001'f32), 0'f32, 1'f32)
        distance = length(p - p0 - line * t)
      else:
        distance = sdBezier(p, p0, p1, p2)
      distance -= strokeWeight * 0.5'f32
      if cap in {scButt, scSquare}:
        let
          start =
            if length(p1 - p0) > 0:
              normalize(p1 - p0)
            else:
              if length(p2 - p0) > 0:
                normalize(p2 - p0)
              else:
                vec2(1, 0)
          stop =
            if length(p2 - p1) > 0:
              normalize(p2 - p1)
            else:
              start
          extension =
            if cap == scSquare:
              strokeWeight * 0.5'f32
            else:
              0'f32
        distance = max(
          distance, max(-dot(p - p0, start) - extension, dot(p - p2, stop) - extension)
        )
      withCoverage(
        sampleFill(fill, (p + center - rect.xy) / rect.wh), coverage(distance, aa)
      ),
  )

proc drawDistanceImage(
    ctx: SoftwareContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange, threshold, strokeWeight: float32,
    flipY, useAlpha: bool,
) =
  if path notin ctx.entries or path notin ctx.images:
    raise newException(KeyError, "Software distance image is not cached: " & $path)
  let
    params = MsdfBitmapParams(
      image: ctx.images[path],
      pxRange: pxRange,
      sdThreshold: threshold,
      flipY: flipY,
      useAlpha: useAlpha,
    )
    center = pos + size * 0.5'f32
  ctx.rasterize(
    rect(pos.x, pos.y, size.x, size.y),
    proc(p: Vec2, aa: float32): ColorRGBX =
      var distance = sdMsdfBitmap(p - center, size, params)
      if strokeWeight > 0:
        distance = abs(distance) - strokeWeight * 0.5'f32
      withCoverage(color.rgba(), coverage(distance, aa)),
  )

method drawMsdfImage*(
    ctx: SoftwareContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange, sdThreshold, strokeWeight: float32,
    flipY: bool,
) =
  ctx.drawDistanceImage(
    path, pos, color, size, pxRange, sdThreshold, strokeWeight, flipY, false
  )

method drawMtsdfImage*(
    ctx: SoftwareContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange, sdThreshold, strokeWeight: float32,
    flipY: bool,
) =
  ctx.drawDistanceImage(
    path, pos, color, size, pxRange, sdThreshold, strokeWeight, flipY, true
  )

method drawBackdropBlur*(
    ctx: SoftwareContext, rect: Rect, radii: CornerRadii2D[float32], blurRadius: float32
) =
  if blurRadius > 0:
    let blurred = ctx.backing.copy()
    blurred.blur(blurRadius * ctx.pixelScaleValue)
    let
      center = rect.xy + rect.wh * 0.5'f32
      mat = ctx.transform
    # Replace covered pixels with the blurred backdrop, including alpha.
    # Interpolating premultiplied channels avoids compositing translucency twice.
    let original = ctx.backing.copy()
    let field = roundedField(rect.wh * 0.5'f32, radii)
    proc sampleBlur(p: Vec2, aa, distance: float32): ColorRGBX =
      let screen = mat * p - vec2(0.5'f32, 0.5'f32)
      let alpha = coverage(distance, aa)
      mixPixel(
        blurred.getRgbaSmooth(screen.x, screen.y),
        original.getRgbaSmooth(screen.x, screen.y),
        round(alpha * 255).uint8,
      )

    var sampleBatch: PixelBatchSampler
    when softwareSimdEnabled:
      sampleBatch = proc(points: array[4, Vec2], aa: float32): array[4, ColorRGBX] =
        var local: array[4, Vec2]
        for lane in 0 ..< 4:
          local[lane] = points[lane] - center
        let distances = field.distances(local)
        for lane in 0 ..< 4:
          result[lane] = sampleBlur(points[lane], aa, distances[lane])
    ctx.rasterize(
      rect,
      proc(p: Vec2, aa: float32): ColorRGBX =
        sampleBlur(p, aa, field.distance(p - center)),
      replace = true,
      sampleBatch = sampleBatch,
    )
