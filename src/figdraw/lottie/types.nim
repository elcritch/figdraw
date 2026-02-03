import std/[options, json]

import pkg/jsony

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
    a*: int
    kValue*: T
    kFrames*: seq[LottieKeyframe[T]]

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
    p*: Option[LottieProperty[seq[float32]]]
    s*: Option[LottieProperty[seq[float32]]]
    c*: Option[LottieProperty[seq[float32]]]
    o*: Option[LottieProperty[float32]]
    fillRule*: Option[int]
    np*: Option[float32]
    it*: seq[LottieShape]
    a*: Option[LottieProperty[seq[float32]]]
    r*: Option[LottieProperty[float32]]
    sk*: Option[LottieProperty[float32]]
    sa*: Option[LottieProperty[float32]]

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

proc parseHook*[T](s: string, i: var int, v: var LottieProperty[T]) =
  var node: JsonNode
  parseHook(s, i, node)
  v = default(LottieProperty[T])
  if node.kind != JObject:
    return
  if node.hasKey("a"):
    v.a = node["a"].getInt.int
  if node.hasKey("k"):
    let kNode = node["k"]
    if v.a == 1:
      v.kFrames = jsony.fromJson($kNode, seq[LottieKeyframe[T]])
    else:
      v.kValue = jsony.fromJson($kNode, T)

proc parseHook*(s: string, i: var int, v: var LottieShape) =
  var node: JsonNode
  parseHook(s, i, node)
  v = default(LottieShape)
  if node.kind != JObject:
    return
  if node.hasKey("ty"):
    v.ty = node["ty"].getStr()
  if node.hasKey("nm"):
    v.nm = node["nm"].getStr()

  template parseProp(key: string, field: untyped, T: typedesc) =
    if node.hasKey(key):
      let value = jsony.fromJson($node[key], LottieProperty[T])
      field = some(value)

  parseProp("p", v.p, seq[float32])
  parseProp("s", v.s, seq[float32])
  parseProp("c", v.c, seq[float32])
  parseProp("o", v.o, float32)
  parseProp("a", v.a, seq[float32])
  parseProp("sk", v.sk, float32)
  parseProp("sa", v.sa, float32)

  if node.hasKey("np"):
    v.np = some(node["np"].getFloat.float32)
  if node.hasKey("it"):
    v.it = jsony.fromJson($node["it"], seq[LottieShape])
  if node.hasKey("r"):
    if v.ty == "fl":
      v.fillRule = some(node["r"].getInt.int)
    else:
      let rot = jsony.fromJson($node["r"], LottieProperty[float32])
      v.r = some(rot)
