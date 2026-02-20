import std/math

import pkg/chroma

type
  FillGradientAxis* = enum
    fgaX
    fgaY
    fgaDiagTLBR
    fgaDiagBLTR

  FillKind* = enum
    flColor
    flLinear2
    flLinear3

  Linear2* = object
    axis*: FillGradientAxis
    start*: ColorRGBA # packed RGBA8
    stop*: ColorRGBA # packed RGBA8

  Linear3* = object
    axis*: FillGradientAxis
    start*: ColorRGBA # packed RGBA8
    mid*: ColorRGBA # packed RGBA8
    stop*: ColorRGBA # packed RGBA8
    midPos*: uint8 # 0..255

  Fill* = object
    case kind*: FillKind
    of flColor:
      color*: ColorRGBA
    of flLinear2:
      lin2*: Linear2
    of flLinear3:
      lin3*: Linear3

proc fill*(color: ColorRGBA): Fill =
  Fill(kind: flColor, color: color)

proc linear*(start, stop: ColorRGBA, axis: FillGradientAxis): Fill =
  Fill(kind: flLinear2, lin2: Linear2(axis: axis, start: start, stop: stop))

proc linear*(
    start, mid, stop: ColorRGBA, axis: FillGradientAxis, midPos = 128'u8
): Fill =
  Fill(
    kind: flLinear3,
    lin3: Linear3(axis: axis, start: start, mid: mid, stop: stop, midPos: midPos),
  )

converter toFill*(c: ColorRGBA): Fill {.inline.} =
  fill(c)

converter toFill*(c: Color): Fill {.inline.} =
  fill(rgba(c))

func lerpColor(a, b: ColorRGBA, t: float32): ColorRGBA =
  let
    clampedT = clamp(t, 0.0'f32, 1.0'f32)
    invT = 1.0'f32 - clampedT
  result.r = (a.r.float32 * invT + b.r.float32 * clampedT).round().uint8
  result.g = (a.g.float32 * invT + b.g.float32 * clampedT).round().uint8
  result.b = (a.b.float32 * invT + b.b.float32 * clampedT).round().uint8
  result.a = (a.a.float32 * invT + b.a.float32 * clampedT).round().uint8

func sampleColor*(fill: Fill, t: float32): ColorRGBA =
  case fill.kind
  of flColor:
    fill.color
  of flLinear2:
    lerpColor(fill.lin2.start, fill.lin2.stop, t)
  of flLinear3:
    let
      clampedT = clamp(t, 0.0'f32, 1.0'f32)
      mid = clamp(fill.lin3.midPos.float32 / 255.0'f32, 0.01'f32, 0.99'f32)
    if clampedT <= mid:
      lerpColor(fill.lin3.start, fill.lin3.mid, clampedT / mid)
    else:
      lerpColor(fill.lin3.mid, fill.lin3.stop, (clampedT - mid) / (1.0'f32 - mid))

func centerColorRgba*(fill: Fill): ColorRGBA =
  sampleColor(fill, 0.5'f32)

func centerColor*(fill: Fill): Color =
  fill.centerColorRgba().color
