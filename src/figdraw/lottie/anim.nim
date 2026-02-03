import std/[math, options]

import ./types

proc handleValue(vals: seq[float32], fallback: float32): float32 =
  if vals.len > 0:
    vals[0]
  else:
    fallback

proc cubicBezier(t, p0, p1, p2, p3: float32): float32 =
  let u = 1.0'f32 - t
  (u * u * u * p0) + (3.0'f32 * u * u * t * p1) +
    (3.0'f32 * u * t * t * p2) + (t * t * t * p3)

proc cubicBezierDerivative(t, p0, p1, p2, p3: float32): float32 =
  let u = 1.0'f32 - t
  (3.0'f32 * u * u * (p1 - p0)) + (6.0'f32 * u * t * (p2 - p1)) +
    (3.0'f32 * t * t * (p3 - p2))

proc bezierEase(progress: float32; outHandle, inHandle: LottieBezier): float32 =
  let x1 = handleValue(outHandle.x, 0.0'f32)
  let y1 = handleValue(outHandle.y, 0.0'f32)
  let x2 = handleValue(inHandle.x, 1.0'f32)
  let y2 = handleValue(inHandle.y, 1.0'f32)

  var t = clamp(progress, 0.0'f32, 1.0'f32)
  for _ in 0 ..< 8:
    let x = cubicBezier(t, 0.0'f32, x1, x2, 1.0'f32)
    let dx = cubicBezierDerivative(t, 0.0'f32, x1, x2, 1.0'f32)
    if abs(dx) < 1.0e-5'f32:
      break
    t = clamp(t - (x - progress) / dx, 0.0'f32, 1.0'f32)
  cubicBezier(t, 0.0'f32, y1, y2, 1.0'f32)

proc lerpValue[T](a, b: T; t: float32): T =
  when T is float32:
    a + (b - a) * t
  elif T is float64:
    a + (b - a) * t
  elif T is seq[float32]:
    result = newSeq[float32](max(a.len, b.len))
    for i in 0 ..< result.len:
      let av = if i < a.len: a[i] else: 0.0'f32
      let bv = if i < b.len: b[i] else: 0.0'f32
      result[i] = av + (bv - av) * t
  else:
    result = a

proc keyframeValue[T](keys: seq[LottieKeyframe[T]], frame: float32): T =
  if keys.len == 0:
    return default(T)
  if frame <= keys[0].t:
    return keys[0].s

  for idx in 0 ..< keys.len - 1:
    let k0 = keys[idx]
    let k1 = keys[idx + 1]
    if frame < k1.t:
      if k0.h.get(0) == 1:
        return k0.s
      let span = k1.t - k0.t
      if span <= 0.0'f32:
        return k1.s
      let startVal = k0.s
      let endVal = if k0.e.isSome: k0.e.get else: k1.s
      let rawT = clamp((frame - k0.t) / span, 0.0'f32, 1.0'f32)
      let eased =
        if k0.o.isSome and k0.i.isSome:
          bezierEase(rawT, k0.o.get, k0.i.get)
        else:
          rawT
      return lerpValue(startVal, endVal, eased)

  keys[^1].s

proc valueAt*[T](prop: LottieProperty[T], frame: float32, fallback: T): T =
  case prop.a
  of 0:
    when T is seq[float32]:
      if prop.kValue.len == 0:
        fallback
      else:
        prop.kValue
    else:
      prop.kValue
  of 1:
    if prop.kFrames.len == 0:
      fallback
    else:
      keyframeValue(prop.kFrames, frame)
  else:
    fallback

proc valueAtOr*[T](prop: Option[LottieProperty[T]], frame: float32, fallback: T): T =
  if prop.isSome:
    valueAt(prop.get, frame, fallback)
  else:
    fallback
