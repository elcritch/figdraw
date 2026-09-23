## Small Core Graphics surface used by the Quartz backend.
##
## The darwin package already supplies the Core Graphics handle and geometry
## types. These declarations keep the backend-specific calls together and avoid
## expanding the general purpose darwin bindings for this experimental backend.

{.passL: "-framework CoreGraphics".}

import darwin/core_foundation/cfbase
import
  darwin/core_graphics/[
    cgcontext, cgpath, cggeometry, cgaffine_transform, cgcolor_space, cgbitmap_context,
    cgimage,
  ]

export cfbase
export
  cgcontext, cgpath, cggeometry, cgaffine_transform, cgcolor_space, cgbitmap_context,
  cgimage

type
  CGPathDrawingMode* {.size: sizeof(int32).} = enum
    kCGPathFill
    kCGPathEOFill
    kCGPathStroke
    kCGPathFillStroke
    kCGPathEOFillStroke

  CGGradient* = ptr object of CFObject

  CGBlendMode* {.size: sizeof(int32).} = enum
    kCGBlendModeNormal

  CGInterpolationQuality* {.size: sizeof(int32).} = enum
    kCGInterpolationDefault
    kCGInterpolationNone
    kCGInterpolationLow
    kCGInterpolationMedium
    kCGInterpolationHigh

proc cgSaveGState*(context: CGContext) {.importc: "CGContextSaveGState".}
proc cgRestoreGState*(context: CGContext) {.importc: "CGContextRestoreGState".}
proc cgTranslateCTM*(
  context: CGContext, tx, ty: CGFloat
) {.importc: "CGContextTranslateCTM".}

proc cgScaleCTM*(context: CGContext, sx, sy: CGFloat) {.importc: "CGContextScaleCTM".}
proc cgRotateCTM*(context: CGContext, angle: CGFloat) {.importc: "CGContextRotateCTM".}
proc cgConcatCTM*(
  context: CGContext, transform: CGAffineTransform
) {.importc: "CGContextConcatCTM".}

proc cgSetRGBFillColor*(
  context: CGContext, r, g, b, a: CGFloat
) {.importc: "CGContextSetRGBFillColor".}

proc cgSetRGBStrokeColor*(
  context: CGContext, r, g, b, a: CGFloat
) {.importc: "CGContextSetRGBStrokeColor".}

proc cgSetAlpha*(context: CGContext, alpha: CGFloat) {.importc: "CGContextSetAlpha".}
proc cgSetLineWidth*(
  context: CGContext, width: CGFloat
) {.importc: "CGContextSetLineWidth".}

proc cgSetLineCap*(
  context: CGContext, cap: CGLineCap
) {.importc: "CGContextSetLineCap".}

proc cgSetLineJoin*(
  context: CGContext, join: CGLineJoin
) {.importc: "CGContextSetLineJoin".}

proc cgSetMiterLimit*(
  context: CGContext, limit: CGFloat
) {.importc: "CGContextSetMiterLimit".}

proc cgSetShouldAntialias*(
  context: CGContext, shouldAntialias: bool
) {.importc: "CGContextSetShouldAntialias".}

proc cgSetAllowsAntialiasing*(
  context: CGContext, allowsAntialiasing: bool
) {.importc: "CGContextSetAllowsAntialiasing".}

proc cgSetInterpolationQuality*(
  context: CGContext, quality: CGInterpolationQuality
) {.importc: "CGContextSetInterpolationQuality".}

proc cgSetBlendMode*(
  context: CGContext, mode: CGBlendMode
) {.importc: "CGContextSetBlendMode".}

proc cgFillRect*(context: CGContext, rect: CGRect) {.importc: "CGContextFillRect".}
proc cgClearRect*(context: CGContext, rect: CGRect) {.importc: "CGContextClearRect".}
proc cgAddPath*(context: CGContext, path: CGPath) {.importc: "CGContextAddPath".}
proc cgDrawPath*(
  context: CGContext, mode: CGPathDrawingMode
) {.importc: "CGContextDrawPath".}

proc cgClip*(context: CGContext) {.importc: "CGContextClip".}
proc cgClipToRect*(context: CGContext, rect: CGRect) {.importc: "CGContextClipToRect".}
proc cgDrawImage*(
  context: CGContext, rect: CGRect, image: CGImage
) {.importc: "CGContextDrawImage".}

proc cgSetShadow*(
  context: CGContext, offset: CGSize, blur: CGFloat
) {.importc: "CGContextSetShadow".}

proc CGGradientCreateWithColorComponents*(
  space: CGColorSpace, components: ptr CGFloat, locations: ptr CGFloat, count: csize_t
): CGGradient {.importc.}

proc CGContextDrawLinearGradient*(
  context: CGContext,
  gradient: CGGradient,
  startPoint, endPoint: CGPoint,
  options: uint32,
) {.importc.}
