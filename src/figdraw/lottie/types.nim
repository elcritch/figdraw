import std/[options]

import std/jsonutils

const LottieJsonOptions* = Joptions(allowExtraKeys: true, allowMissingKeys: true)

type
  LottieBezier* = object
    x*: seq[float32]
    y*: seq[float32]

  LottieKeyframe*[T] = object
    t*: float32
    s*: T
    e*: Option[T]
    i*: Option[LottieBezier]
    o*: Option[LottieBezier]
    h*: Option[int]

  LottieProperty*[T] = object
    case a*: range[0..1]
    of 0:
      k*: T
    of 1:
      k*: seq[LottieKeyframe[T]]
    else:
      k*: T

  LottieTransform* = object
    a*: Option[LottieProperty[seq[float32]]]
    p*: Option[LottieProperty[seq[float32]]]
    s*: Option[LottieProperty[seq[float32]]]
    r*: Option[LottieProperty[float32]]
    o*: Option[LottieProperty[float32]]
    sk*: Option[LottieProperty[float32]]
    sa*: Option[LottieProperty[float32]]

  LottieShape* = object
    ty*: string
    nm*: string
    case ty*: string
    of "el":
      p*: LottieProperty[seq[float32]]
      s*: LottieProperty[seq[float32]]
    of "fl":
      c*: LottieProperty[seq[float32]]
      o*: LottieProperty[float32]
      r*: int
    of "gr":
      np*: float32
      it*: seq[LottieShape]
    of "tr":
      a*: Option[LottieProperty[seq[float32]]]
      p*: Option[LottieProperty[seq[float32]]]
      s*: Option[LottieProperty[seq[float32]]]
      r*: Option[LottieProperty[float32]]
      o*: Option[LottieProperty[float32]]
      sk*: Option[LottieProperty[float32]]
      sa*: Option[LottieProperty[float32]]
    else:
      discard

  LottieLayer* = object
    ty*: int
    nm*: string
    ind*: int
    ip*: float32
    op*: float32
    st*: float32
    ks*: LottieTransform
    shapes*: seq[LottieShape]

  LottieAnimation* = object
    nm*: string
    v*: string
    ver*: int
    fr*: float32
    ip*: float32
    op*: float32
    w*: int
    h*: int
    layers*: seq[LottieLayer]
