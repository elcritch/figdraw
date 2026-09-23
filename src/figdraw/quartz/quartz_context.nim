## Experimental macOS Quartz 2D backend.
##
## This backend deliberately targets the small, useful 2D subset first. It
## renders into a Core Graphics bitmap context, which makes it useful for
## deterministic captures and PDF/window integration later without requiring a
## Metal drawable or a live window.

when not defined(macosx):
  {.error: "figdraw/quartz is only available on macOS".}

import std/[hashes, math, tables]

import pkg/[chroma, pixie]
import vmath

import ../commons
import ../figbackend
import ../fignodes
import ./quartz_bindings

type QuartzContext* = ref object of BackendContext
  context: CGContext
  backing: Image
  frameSize: Vec2
  pixelScaleValue: float32
  entries: Table[Hash, Rect]
  atlasEntryMeta: Table[Hash, AtlasEntryMeta]
  images: Table[Hash, Image]
  transformMirrored: bool
  savedBaseState: bool

const CubicKappa = 0.5522847498'f32

func cgRect(rect: Rect): CGRect =
  CGRect(
    origin: CGPoint(x: rect.x.CGFloat, y: rect.y.CGFloat),
    size: CGSize(width: rect.w.CGFloat, height: rect.h.CGFloat),
  )

func cgColorComponent(value: uint8): CGFloat =
  value.float32.CGFloat / 255.0.CGFloat

proc setFillColor(context: CGContext, color: ColorRGBA) =
  context.cgSetRGBFillColor(
    cgColorComponent(color.r),
    cgColorComponent(color.g),
    cgColorComponent(color.b),
    cgColorComponent(color.a),
  )

proc setStrokeColor(context: CGContext, color: ColorRGBA) =
  context.cgSetRGBStrokeColor(
    cgColorComponent(color.r),
    cgColorComponent(color.g),
    cgColorComponent(color.b),
    cgColorComponent(color.a),
  )

func backendFillCenter(fill: BackendFill): ColorRGBA =
  case fill.kind
  of bfColor:
    fill.color
  of bfLinear2:
    let a = fill.lin2Start
    let b = fill.lin2Stop
    rgba(
      ((a.r.uint16 + b.r.uint16) div 2).uint8,
      ((a.g.uint16 + b.g.uint16) div 2).uint8,
      ((a.b.uint16 + b.b.uint16) div 2).uint8,
      ((a.a.uint16 + b.a.uint16) div 2).uint8,
    )
  of bfLinear3:
    fill.lin3Mid

func averageColors(colors: array[4, ColorRGBA]): ColorRGBA =
  rgba(
    ((colors[0].r.uint32 + colors[1].r + colors[2].r + colors[3].r) div 4).uint8,
    ((colors[0].g.uint32 + colors[1].g + colors[2].g + colors[3].g) div 4).uint8,
    ((colors[0].b.uint32 + colors[1].b + colors[2].b + colors[3].b) div 4).uint8,
    ((colors[0].a.uint32 + colors[1].a + colors[2].a + colors[3].a) div 4).uint8,
  )

func backendFillAxis(fill: BackendFill): FillGradientAxis =
  case fill.kind
  of bfColor: fgaX
  of bfLinear2: fill.lin2Axis
  of bfLinear3: fill.lin3Axis

func fillAlphaMax(fill: Fill): uint8 =
  case fill.kind
  of flColor:
    fill.color.a
  of flLinear2:
    max(fill.lin2.start.a, fill.lin2.stop.a)
  of flLinear3:
    max(fill.lin3.start.a, max(fill.lin3.mid.a, fill.lin3.stop.a))

proc addRoundedPath(path: CGMutablePath, rect: Rect, radii: CornerRadii2D[float32]) =
  if rect.w <= 0.0'f32 or rect.h <= 0.0'f32:
    return

  let
    halfWidth = rect.w * 0.5'f32
    halfHeight = rect.h * 0.5'f32
    tlx = clamp(radii.x[dcTopLeft], 0.0'f32, halfWidth)
    trx = clamp(radii.x[dcTopRight], 0.0'f32, halfWidth)
    blx = clamp(radii.x[dcBottomLeft], 0.0'f32, halfWidth)
    brx = clamp(radii.x[dcBottomRight], 0.0'f32, halfWidth)
    tly = clamp(radii.y[dcTopLeft], 0.0'f32, halfHeight)
    tryr = clamp(radii.y[dcTopRight], 0.0'f32, halfHeight)
    bly = clamp(radii.y[dcBottomLeft], 0.0'f32, halfHeight)
    bry = clamp(radii.y[dcBottomRight], 0.0'f32, halfHeight)
    x0 = rect.x
    y0 = rect.y
    x1 = rect.x + rect.w
    y1 = rect.y + rect.h
    k = CubicKappa

  path.moveToPoint(nil, (x0 + tlx).CGFloat, y0.CGFloat)
  path.addLineToPoint(nil, (x1 - trx).CGFloat, y0.CGFloat)
  path.addCurveToPoint(
    nil,
    (x1 - trx + trx * k).CGFloat,
    y0.CGFloat,
    x1.CGFloat,
    (y0 + tryr - tryr * k).CGFloat,
    x1.CGFloat,
    (y0 + tryr).CGFloat,
  )
  path.addLineToPoint(nil, x1.CGFloat, (y1 - bry).CGFloat)
  path.addCurveToPoint(
    nil,
    x1.CGFloat,
    (y1 - bry + bry * k).CGFloat,
    (x1 - brx + brx * k).CGFloat,
    y1.CGFloat,
    (x1 - brx).CGFloat,
    y1.CGFloat,
  )
  path.addLineToPoint(nil, (x0 + blx).CGFloat, y1.CGFloat)
  path.addCurveToPoint(
    nil,
    (x0 + blx - blx * k).CGFloat,
    y1.CGFloat,
    x0.CGFloat,
    (y1 - bly + bly * k).CGFloat,
    x0.CGFloat,
    (y1 - bly).CGFloat,
  )
  path.addLineToPoint(nil, x0.CGFloat, (y0 + tly).CGFloat)
  path.addCurveToPoint(
    nil,
    x0.CGFloat,
    (y0 + tly - tly * k).CGFloat,
    (x0 + tlx - tlx * k).CGFloat,
    y0.CGFloat,
    (x0 + tlx).CGFloat,
    y0.CGFloat,
  )
  path.closeSubpath()

proc drawGradient(
    context: CGContext, rect: Rect, fill: BackendFill, colorSpace: CGColorSpace
) =
  var
    components: array[12, CGFloat]
    locations: array[3, CGFloat]
    count: csize_t

  proc putColor(offset: int, color: ColorRGBA) =
    components[offset + 0] = cgColorComponent(color.r)
    components[offset + 1] = cgColorComponent(color.g)
    components[offset + 2] = cgColorComponent(color.b)
    components[offset + 3] = cgColorComponent(color.a)

  case fill.kind
  of bfColor:
    return
  of bfLinear2:
    putColor(0, fill.lin2Start)
    putColor(4, fill.lin2Stop)
    locations[0] = 0.0.CGFloat
    locations[1] = 1.0.CGFloat
    count = 2
  of bfLinear3:
    putColor(0, fill.lin3Start)
    putColor(4, fill.lin3Mid)
    putColor(8, fill.lin3Stop)
    locations[0] = 0.0.CGFloat
    locations[1] = fill.lin3MidPos.CGFloat
    locations[2] = 1.0.CGFloat
    count = 3

  let gradient = CGGradientCreateWithColorComponents(
    colorSpace, components[0].addr, locations[0].addr, count
  )
  if gradient.isNil:
    return

  var startPoint, endPoint: CGPoint
  case backendFillAxis(fill)
  of fgaX:
    startPoint = CGPoint(x: rect.x.CGFloat, y: rect.y.CGFloat)
    endPoint = CGPoint(x: (rect.x + rect.w).CGFloat, y: rect.y.CGFloat)
  of fgaY:
    startPoint = CGPoint(x: rect.x.CGFloat, y: rect.y.CGFloat)
    endPoint = CGPoint(x: rect.x.CGFloat, y: (rect.y + rect.h).CGFloat)
  of fgaDiagTLBR:
    startPoint = CGPoint(x: rect.x.CGFloat, y: rect.y.CGFloat)
    endPoint = CGPoint(x: (rect.x + rect.w).CGFloat, y: (rect.y + rect.h).CGFloat)
  of fgaDiagBLTR:
    startPoint = CGPoint(x: rect.x.CGFloat, y: (rect.y + rect.h).CGFloat)
    endPoint = CGPoint(x: (rect.x + rect.w).CGFloat, y: rect.y.CGFloat)

  CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, 0'u32)
  release(cast[CFObject](gradient))

proc fillPath(
    context: CGContext,
    path: CGPath,
    rect: Rect,
    fill: BackendFill,
    colorSpace: CGColorSpace,
) =
  case fill.kind
  of bfColor:
    setFillColor(context, fill.color)
    context.cgAddPath(path)
    context.cgDrawPath(kCGPathFill)
  of bfLinear2, bfLinear3:
    context.cgSaveGState()
    context.cgAddPath(path)
    context.cgClip()
    drawGradient(context, rect, fill, colorSpace)
    context.cgRestoreGState()

proc configureStroke(context: CGContext, stroke: RenderStroke, weight: float32) =
  setStrokeColor(context, stroke.fill.centerColorRgba())
  context.cgSetLineWidth(max(0.0'f32, weight).CGFloat)
  context.cgSetMiterLimit(4.0.CGFloat)
  context.cgSetLineCap(
    case stroke.cap
    of scRound: kCGLineCapRound
    of scSquare: kCGLineCapSquare
    of scAuto, scButt: kCGLineCapButt
  )
  context.cgSetLineJoin(
    case stroke.join
    of sjRound: kCGLineJoinRound
    of sjBevel: kCGLineJoinBevel
    of sjAuto, sjMiter: kCGLineJoinMiter
  )

proc strokePath(
    context: CGContext, path: CGPath, stroke: RenderStroke, weight: float32
) =
  if weight <= 0.0'f32 or fillAlphaMax(stroke.fill) == 0'u8:
    return
  configureStroke(context, stroke, weight)
  context.cgAddPath(path)
  context.cgDrawPath(kCGPathStroke)

proc releaseContext(ctx: QuartzContext) =
  if not ctx.context.isNil:
    ctx.context.release()
    ctx.context = nil
  ctx.backing = nil

proc beginBitmap(ctx: QuartzContext, frameSize: Vec2) =
  ctx.releaseContext()
  let
    width = max(1, round(frameSize.x).int)
    height = max(1, round(frameSize.y).int)
  ctx.backing = newImage(width, height)
  let colorSpace = CGColorSpaceCreateDeviceRGB()
  if colorSpace.isNil:
    raise newException(ValueError, "Quartz could not create an RGB color space")
  try:
    const bitmapInfo =
      uint32(kCGBitmapByteOrder32Big.ord) or uint32(kCGImageAlphaPremultipliedLast.ord)
    ctx.context = CGBitmapContextCreate(
      ctx.backing.data[0].addr,
      width.csize_t,
      height.csize_t,
      8,
      (width * 4).csize_t,
      colorSpace,
      bitmapInfo,
    )
  finally:
    release(cast[CFObject](colorSpace))
  if ctx.context.isNil:
    raise newException(ValueError, "Quartz could not create a bitmap context")

  ctx.frameSize = vec2(width.float32, height.float32)
  ctx.savedBaseState = true
  ctx.transformMirrored = true
  ctx.context.cgSaveGState()
  # FigDraw uses a top-left, y-down coordinate system. Quartz's bitmap context
  # starts with a bottom-left, y-up user space, so normalize it once per frame.
  ctx.context.cgTranslateCTM(0.0.CGFloat, height.CGFloat)
  ctx.context.cgScaleCTM(1.0.CGFloat, -1.0.CGFloat)
  ctx.context.cgSetShouldAntialias(true)
  ctx.context.cgSetAllowsAntialiasing(true)

proc clearBitmap(ctx: QuartzContext, color: Color) =
  setFillColor(ctx.context, color.rgba())
  ctx.context.cgFillRect(cgRect(rect(0, 0, ctx.frameSize.x, ctx.frameSize.y)))

proc drawRounded(
    ctx: QuartzContext,
    rect: Rect,
    fill: BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    strokeWeight: float32 = 0.0'f32,
    stroke: RenderStroke = RenderStroke(),
) =
  if rect.w <= 0.0'f32 or rect.h <= 0.0'f32:
    return
  if mode in {
    sdfModeDropShadow, sdfModeDropShadowAA, sdfModeInsetShadow,
    sdfModeInsetShadowAnnular, sdfModeBackdropBlur,
  }:
    return

  let path = CGPathCreateMutable()
  if path.isNil:
    return
  try:
    addRoundedPath(path, rect, radii)
    if mode in {sdfModeAnnular, sdfModeAnnularAA}:
      var actualStroke = stroke
      actualStroke.fill = backendFillCenter(fill)
      strokePath(ctx.context, path, actualStroke, strokeWeight)
    else:
      let colorSpace = CGColorSpaceCreateDeviceRGB()
      if not colorSpace.isNil:
        try:
          fillPath(ctx.context, path, rect, fill, colorSpace)
        finally:
          release(cast[CFObject](colorSpace))
  finally:
    path.release()

proc drawRoundedColors(
    ctx: QuartzContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    strokeWeight: float32,
) =
  let fill = BackendFill(kind: bfColor, color: averageColors(colors))
  ctx.drawRounded(rect, fill, radii, mode, strokeWeight)

method kind*(ctx: QuartzContext): RendererBackendKind =
  rbQuartz

method supportsAtlasUsage*(ctx: QuartzContext): bool =
  false

method entriesPtr*(ctx: QuartzContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method atlasEntryMetaPtr*(ctx: QuartzContext): var Table[Hash, AtlasEntryMeta] =
  ctx.atlasEntryMeta

method atlasSize*(ctx: QuartzContext): int =
  0

method atlasPackedArea*(ctx: QuartzContext): int =
  0

method pixelScale*(ctx: QuartzContext): float32 =
  ctx.pixelScaleValue

method hasImage*(ctx: QuartzContext, key: Hash): bool =
  key in ctx.images and not ctx.images[key].isNil

method putImage*(ctx: QuartzContext, path: Hash, image: Image) =
  if image.isNil:
    return
  ctx.images[path] = image
  ctx.entries[path] = rect(0, 0, image.width.float32, image.height.float32)

method updateImage*(ctx: QuartzContext, path: Hash, image: Image) =
  ctx.putImage(path, image)

method addImage*(ctx: QuartzContext, key: Hash, image: Image) =
  ctx.putImage(key, image)

method putImage*(ctx: QuartzContext, imgObj: ImgObj) =
  case imgObj.kind
  of PixieImg:
    ctx.putImage(imgObj.id.Hash, imgObj.pimg)
  else:
    discard

method removeImage*(ctx: QuartzContext, id: ImageId) =
  ctx.images.del(id.Hash)
  ctx.entries.del(id.Hash)
  ctx.atlasEntryMeta.del(id.Hash)

method clearImageAtlas*(ctx: QuartzContext) =
  ctx.images.clear()
  ctx.entries.clear()
  ctx.atlasEntryMeta.clear()

method resetImageAtlas*(ctx: QuartzContext, minimumSize: int) =
  discard minimumSize
  ctx.clearImageAtlas()

method drawRect*(ctx: QuartzContext, rect: Rect, color: Color) =
  setFillColor(ctx.context, color.rgba())
  ctx.context.cgFillRect(cgRect(rect))

method drawFilledQuad*(
    ctx: QuartzContext, verts: array[4, Vec2], colors: array[4, ColorRGBA]
) =
  let path = CGPathCreateMutable()
  if path.isNil:
    return
  try:
    path.moveToPoint(nil, verts[0].x.CGFloat, verts[0].y.CGFloat)
    for i in 1 .. 3:
      path.addLineToPoint(nil, verts[i].x.CGFloat, verts[i].y.CGFloat)
    path.closeSubpath()
    setFillColor(ctx.context, averageColors(colors))
    ctx.context.cgAddPath(path)
    ctx.context.cgDrawPath(kCGPathFill)
  finally:
    path.release()

method drawQuadraticBezierSdf*(
    ctx: QuartzContext,
    rect: Rect,
    fill: BackendFill,
    p0, p1, p2: Vec2,
    strokeWeight: float32,
    cap: StrokeCap,
) =
  let path = CGPathCreateMutable()
  if path.isNil:
    return
  try:
    let center = rect.xy + rect.wh * 0.5'f32
    path.moveToPoint(nil, (center.x + p0.x).CGFloat, (center.y + p0.y).CGFloat)
    path.addQuadCurveToPoint(
      nil,
      (center.x + p1.x).CGFloat,
      (center.y + p1.y).CGFloat,
      (center.x + p2.x).CGFloat,
      (center.y + p2.y).CGFloat,
    )
    var stroke = RenderStroke(weight: strokeWeight, fill: backendFillCenter(fill))
    stroke.cap = cap
    stroke.join = sjRound
    strokePath(ctx.context, path, stroke, strokeWeight)
  finally:
    path.release()

method drawRoundedRectSdf*(
    ctx: QuartzContext,
    rect: Rect,
    fill: BackendFill,
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) =
  discard spread
  discard shapeSize
  ctx.drawRounded(rect, fill, radii, mode, factor)

method drawRoundedRectSdf*(
    ctx: QuartzContext,
    rect: Rect,
    colors: array[4, ColorRGBA],
    radii: CornerRadii2D[float32],
    mode: SdfMode,
    factor: float32,
    spread: float32,
    shapeSize: Vec2,
) =
  discard spread
  discard shapeSize
  ctx.drawRoundedColors(rect, colors, radii, mode, factor)

method drawImage*(
    ctx: QuartzContext,
    path: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  if path notin ctx.images or ctx.images[path].isNil or ctx.context.isNil:
    return
  let image = ctx.images[path]
  if image.width <= 0 or image.height <= 0 or image.data.len == 0:
    return

  let colorSpace = CGColorSpaceCreateDeviceRGB()
  if colorSpace.isNil:
    return
  let bitmapInfo =
    uint32(kCGBitmapByteOrder32Big.ord) or uint32(kCGImageAlphaPremultipliedLast.ord)
  let imageContext = CGBitmapContextCreate(
    image.data[0].addr,
    image.width.csize_t,
    image.height.csize_t,
    8,
    (image.width * 4).csize_t,
    colorSpace,
    bitmapInfo,
  )
  if imageContext.isNil:
    release(cast[CFObject](colorSpace))
    return
  let cgImage = imageContext.createImage()
  if not cgImage.isNil:
    let drawSize =
      if size.x > 0.0'f32 and size.y > 0.0'f32:
        size
      else:
        vec2(image.width.float32, image.height.float32)
    let tint = averageColors(colors)
    imageContext.release()
    release(cast[CFObject](colorSpace))
    try:
      ctx.context.cgSaveGState()
      ctx.context.cgSetInterpolationQuality(kCGInterpolationHigh)
      if tint.a < 255'u8:
        # This preserves the common opacity use case while keeping the image
        # path simple. Full per-channel tinting can be added with a mask later.
        ctx.context.cgSetAlpha(cgColorComponent(tint.a))
      # CGContextDrawImage uses the bitmap's lower-left image origin. Flip the
      # image into FigDraw's top-left image convention unless the caller asked
      # for an explicit Y inversion.
      if not flipY:
        ctx.context.cgTranslateCTM(pos.x.CGFloat, (pos.y + drawSize.y).CGFloat)
        ctx.context.cgScaleCTM(1.0.CGFloat, -1.0.CGFloat)
        ctx.context.cgDrawImage(cgRect(rect(0, 0, drawSize.x, drawSize.y)), cgImage)
      else:
        ctx.context.cgDrawImage(
          cgRect(rect(pos.x, pos.y, drawSize.x, drawSize.y)), cgImage
        )
      ctx.context.cgRestoreGState()
    finally:
      cgImage.release()
    return
  imageContext.release()
  release(cast[CFObject](colorSpace))

method drawMsdfImage*(
    ctx: QuartzContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32,
    strokeWeight: float32,
    flipY: bool,
) =
  discard pxRange
  discard sdThreshold
  discard strokeWeight
  let c = color.rgba()
  ctx.drawImage(path, pos, [c, c, c, c], size, flipY)

method drawMtsdfImage*(
    ctx: QuartzContext,
    path: Hash,
    pos: Vec2,
    color: Color,
    size: Vec2,
    pxRange: float32,
    sdThreshold: float32,
    strokeWeight: float32,
    flipY: bool,
) =
  ctx.drawMsdfImage(path, pos, color, size, pxRange, sdThreshold, strokeWeight, flipY)

method drawBackdropBlur*(
    ctx: QuartzContext, rect: Rect, radii: CornerRadii2D[float32], blurRadius: float32
) =
  discard ctx
  discard rect
  discard radii
  discard blurRadius

method beginMask*(ctx: QuartzContext, clipRect: Rect, radii: CornerRadii2D[float32]) =
  ctx.context.cgSaveGState()
  let path = CGPathCreateMutable()
  if not path.isNil:
    addRoundedPath(path, clipRect, radii)
    ctx.context.cgAddPath(path)
    ctx.context.cgClip()
    path.release()

method endMask*(ctx: QuartzContext) =
  discard ctx

method popMask*(ctx: QuartzContext) =
  ctx.context.cgRestoreGState()

method beginRectMask*(
    ctx: QuartzContext, maskRect: Rect, radii: CornerRadii2D[float32]
) =
  ctx.beginMask(maskRect, radii)

method popRectMask*(ctx: QuartzContext) =
  ctx.popMask()

method beginFrame*(
    ctx: QuartzContext, frameSize: Vec2, clearMain: bool, clearMainColor: Color
) =
  ctx.beginBitmap(frameSize)
  if clearMain:
    ctx.clearBitmap(clearMainColor)

method endFrame*(ctx: QuartzContext) =
  if ctx.savedBaseState and not ctx.context.isNil:
    ctx.context.cgRestoreGState()
    ctx.savedBaseState = false

method translate*(ctx: QuartzContext, v: Vec2) =
  ctx.context.cgTranslateCTM(v.x.CGFloat, v.y.CGFloat)

method rotate*(ctx: QuartzContext, angle: float32) =
  ctx.context.cgRotateCTM(angle.CGFloat)

method scale*(ctx: QuartzContext, s: float32) =
  ctx.context.cgScaleCTM(s.CGFloat, s.CGFloat)

method scale*(ctx: QuartzContext, s: Vec2) =
  ctx.context.cgScaleCTM(s.x.CGFloat, s.y.CGFloat)

proc affineTransform(m: Mat4): CGAffineTransform =
  let
    origin = (m * vec3(0.0'f32, 0.0'f32, 1.0'f32)).xy
    xAxis = (m * vec3(1.0'f32, 0.0'f32, 1.0'f32)).xy - origin
    yAxis = (m * vec3(0.0'f32, 1.0'f32, 1.0'f32)).xy - origin
  CGAffineTransform(
    a: xAxis.x.CGFloat,
    b: xAxis.y.CGFloat,
    c: yAxis.x.CGFloat,
    d: yAxis.y.CGFloat,
    tx: origin.x.CGFloat,
    ty: origin.y.CGFloat,
  )

method applyTransform*(ctx: QuartzContext, m: Mat4) =
  ctx.context.cgConcatCTM(affineTransform(m))

method saveTransform*(ctx: QuartzContext) =
  ctx.context.cgSaveGState()

method restoreTransform*(ctx: QuartzContext) =
  ctx.context.cgRestoreGState()

method transformMirrorsY*(ctx: QuartzContext): bool =
  ctx.transformMirrored

method readPixels*(ctx: QuartzContext, frame: Rect, readFront: bool): Image =
  discard readFront
  if ctx.backing.isNil:
    return newImage(1, 1)

  var
    x = frame.x.int
    y = frame.y.int
    width = frame.w.int
    height = frame.h.int
  if width <= 0 or height <= 0:
    x = 0
    y = 0
    width = ctx.backing.width
    height = ctx.backing.height
  x = clamp(x, 0, max(0, ctx.backing.width - 1))
  y = clamp(y, 0, max(0, ctx.backing.height - 1))
  width = min(width, ctx.backing.width - x)
  height = min(height, ctx.backing.height - y)
  if width <= 0 or height <= 0:
    return newImage(1, 1)

  result = newImage(width, height)
  for row in 0 ..< height:
    # The normalized top-left CTM used by this backend also makes the bitmap
    # rows line up with FigDraw's screenshot orientation.
    let sourceY = y + row
    for column in 0 ..< width:
      result.data[result.dataIndex(column, row)] =
        ctx.backing.data[ctx.backing.dataIndex(x + column, sourceY)]

proc captureImage*(ctx: QuartzContext, frame: Rect = rect(0, 0, 0, 0)): Image =
  ctx.readPixels(frame, readFront = true)

proc writeCapture*(ctx: QuartzContext, path: string, frame: Rect = rect(0, 0, 0, 0)) =
  ctx.captureImage(frame).writeFile(path)

method textLcdFilteringEnabled*(ctx: QuartzContext): bool =
  false

method textSubpixelPositioningEnabled*(ctx: QuartzContext): bool =
  false

method textSubpixelGlyphVariantsEnabled*(ctx: QuartzContext): bool =
  false

method setTextLcdFilteringEnabled*(ctx: QuartzContext, enabled: bool) =
  discard

method setTextSubpixelPositioningEnabled*(ctx: QuartzContext, enabled: bool) =
  discard

method setTextSubpixelGlyphVariantsEnabled*(ctx: QuartzContext, enabled: bool) =
  discard

method setTextSubpixelShift*(ctx: QuartzContext, shift: float32) =
  discard

proc newContext*(
    atlasSize = 1024,
    atlasMargin = 4,
    maxQuads = 1024,
    pixelate = false,
    pixelScale = 1.0'f32,
): QuartzContext =
  discard atlasSize
  discard atlasMargin
  discard maxQuads
  discard pixelate
  result = QuartzContext(
    pixelScaleValue: pixelScale,
    entries: initTable[Hash, Rect](),
    atlasEntryMeta: initTable[Hash, AtlasEntryMeta](),
    images: initTable[Hash, Image](),
  )
  result.ensureImageMessageSubscription()
