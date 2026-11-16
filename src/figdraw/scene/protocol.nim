## Optional, versioned CBOR scene interchange. See docs/cbor.md.
import std/[math, unicode]
import cborious
import ../fignodes

const
  SceneWireVersion* = 1
  SceneVersionKey* = 0
  SceneNodesKey* = 1
  SceneGroupCode* = 0
  SceneRectangleCode* = 1
  SceneTextCode* = 2
  SceneImageCode* = 3

type
  SceneWireError* = object of CatchableError
  SceneNodeKind* = enum
    snGroup
    snRectangle
    snText
    snImage

  SceneNode* = object ## Parent is -1 for a root, otherwise an earlier node index.
    parent*: int32 = -1
    bounds*: Rect
    case kind*: SceneNodeKind
    of snGroup: discard
    of snRectangle:
      color*: ColorRGBA
    of snText:
      fontId*: uint64
      text*: string
      textColor*: ColorRGBA = rgba(0, 0, 0, 255)
    of snImage:
      imageId*: uint64

  Scene* = object
    nodes*: seq[SceneNode]

  TextResolver* = proc(
    id: uint64, text: string, bounds: Rect, color: ColorRGBA
  ): GlyphArrangement {.closure.}
  ImageResolver* = proc(id: uint64): ImageId {.closure.}

proc fail(msg: string) {.noreturn.} =
  raise newException(SceneWireError, msg)

proc validate(scene: Scene) =
  if scene.nodes.len > 32767:
    fail("too many scene nodes")
  for i, n in scene.nodes:
    if n.parent < -1 or n.parent >= i:
      fail("invalid parent index")
    for v in [n.bounds.x, n.bounds.y, n.bounds.w, n.bounds.h]:
      if classify(v) in {fcNan, fcInf, fcNegInf}:
        fail("non-finite bounds")
    if n.kind == snText:
      if n.text.len > 1_048_576 or validateUtf8(n.text) != -1:
        fail("invalid or oversized UTF-8 text")

proc putArray(s: CborStream, n: int) =
  s.cborPackInt(n.uint64, CborMajor.Array)

proc putNumber(s: CborStream, x: float32) =
  if x >= -2147483648'f32 and x < 2147483648'f32 and x == trunc(x):
    s.cborPack(x.int64)
  else:
    s.cborPack(x)

proc putColor(s: CborStream, c: ColorRGBA) =
  s.cborPack(
    (uint32(c.r) shl 24) or (uint32(c.g) shl 16) or (uint32(c.b) shl 8) or uint32(c.a)
  )

proc encodeScene*(scene: Scene): string =
  ## Encode a validated scene as one CBOR item.
  scene.validate()
  let s = CborStream.init()
  s.cborPackInt(2, CborMajor.Map)
  s.cborPack(SceneVersionKey)
  s.cborPack(SceneWireVersion)
  s.cborPack(SceneNodesKey)
  s.putArray(scene.nodes.len)
  for n in scene.nodes:
    case n.kind
    of snGroup:
      s.putArray(6)
      s.cborPack(SceneGroupCode)
    of snRectangle:
      s.putArray(7)
      s.cborPack(SceneRectangleCode)
    of snText:
      s.putArray(if n.textColor == rgba(0, 0, 0, 255): 8 else: 9)
      s.cborPack(SceneTextCode)
    of snImage:
      s.putArray(7)
      s.cborPack(SceneImageCode)
    s.cborPack(n.parent)
    for v in [n.bounds.x, n.bounds.y, n.bounds.w, n.bounds.h]:
      s.putNumber(v)
    case n.kind
    of snGroup:
      discard
    of snRectangle:
      s.putColor(n.color)
    of snText:
      s.cborPack(n.fontId)
      s.cborPack(n.text)
      if n.textColor != rgba(0, 0, 0, 255):
        s.putColor(n.textColor)
    of snImage:
      s.cborPack(n.imageId)
    if s.data.len > 16_777_216:
      fail("scene document too large")
  result = s.data

proc header(s: CborStream): tuple[major: CborMajor, value: uint64] =
  if s.atEnd():
    fail("truncated CBOR")
  let (major, ai) = s.readInitial()
  let extra =
    case ai
    of 0 .. 23:
      0
    of 24:
      1
    of 25:
      2
    of 26:
      4
    of 27:
      8
    else:
      fail("invalid or indefinite CBOR item")
  if s.data.len - s.getPosition() < extra:
    fail("truncated CBOR")
  (major, s.readAddInfo(ai))

proc readUint(s: CborStream): uint64 =
  let (major, v) = s.header()
  if major != CborMajor.Unsigned:
    fail("expected unsigned integer")
  v

proc readArray(s: CborStream, maxLen: int): int =
  let (major, v) = s.header()
  if major != CborMajor.Array or v > maxLen.uint64:
    fail("invalid array length")
  v.int

proc readNumber(s: CborStream): float32 =
  let pos = s.getPosition()
  let (major, v) = s.header()
  case major
  of CborMajor.Unsigned:
    result = v.float32
  of CborMajor.Negative:
    result = -1'f32 - v.float32
  of CborMajor.Simple:
    s.setPosition(pos)
    s.cborUnpack(result)
  else:
    fail("expected number")
  if classify(result) in {fcNan, fcInf, fcNegInf}:
    fail("non-finite number")

proc readParent(s: CborStream): int32 =
  let (major, v) = s.header()
  case major
  of CborMajor.Unsigned:
    if v > 32766:
      fail("invalid parent index")
    result = v.int32
  of CborMajor.Negative:
    if v != 0:
      fail("invalid parent index")
    result = -1
  else:
    fail("expected parent index")

proc readColor(s: CborStream): ColorRGBA =
  let v = s.readUint()
  if v > uint32.high.uint64:
    fail("invalid color")
  rgba(
    uint8(v shr 24),
    uint8((v shr 16) and 255),
    uint8((v shr 8) and 255),
    uint8(v and 255),
  )

proc readText(s: CborStream): string =
  let (major, size) = s.header()
  if major != CborMajor.String or size > 1_048_576 or
      size > (s.data.len - s.getPosition()).uint64:
    fail("invalid text length")
  result = s.readStr(size.int)
  if validateUtf8(result) != -1:
    fail("invalid UTF-8 text")

proc decodeScene*(data: string): Scene =
  ## Decode exactly one scene; malformed or unsupported input raises SceneWireError.
  try:
    if data.len > 16_777_216:
      fail("scene document too large")
    let s = CborStream.init(data)
    let (major, size) = s.header()
    if major != CborMajor.Map or size != 2 or s.readUint() != SceneVersionKey.uint64 or
        s.readUint() != SceneWireVersion.uint64 or s.readUint() != SceneNodesKey.uint64:
      fail("unsupported scene version")
    let count = s.readArray(32767)
    for i in 0 ..< count:
      let size = s.readArray(9)
      let kind = s.readUint()
      let parent = s.readParent()
      if parent >= i:
        fail("invalid parent index")
      let bounds = rect(s.readNumber(), s.readNumber(), s.readNumber(), s.readNumber())
      case kind
      of SceneGroupCode:
        if size != 6:
          fail("invalid group")
        result.nodes.add SceneNode(kind: snGroup, parent: parent, bounds: bounds)
      of SceneRectangleCode:
        if size != 7:
          fail("invalid rectangle")
        result.nodes.add SceneNode(
          kind: snRectangle, parent: parent, bounds: bounds, color: s.readColor()
        )
      of SceneTextCode:
        if size != 8 and size != 9:
          fail("invalid text")
        let font = s.readUint()
        let text = s.readText()
        let color =
          if size == 9:
            s.readColor()
          else:
            rgba(0, 0, 0, 255)
        result.nodes.add SceneNode(
          kind: snText,
          parent: parent,
          bounds: bounds,
          fontId: font,
          text: text,
          textColor: color,
        )
      of SceneImageCode:
        if size != 7:
          fail("invalid image")
        result.nodes.add SceneNode(
          kind: snImage, parent: parent, bounds: bounds, imageId: s.readUint()
        )
      else:
        fail("unknown node kind")
    if not s.atEnd():
      fail("trailing data")
    result.validate()
  except SceneWireError:
    raise
  except CatchableError as e:
    fail("invalid CBOR: " & e.msg)

proc toRenderList*(
    scene: Scene, textResolver: TextResolver = nil, imageResolver: ImageResolver = nil
): RenderList =
  ## Resolve resource IDs and build an independent FigDraw render list.
  scene.validate()
  for n in scene.nodes:
    var fig: Fig
    case n.kind
    of snGroup:
      fig = Fig(kind: nkFrame, screenBox: n.bounds)
    of snRectangle:
      fig = Fig(kind: nkRectangle, screenBox: n.bounds, fill: fill(n.color))
    of snText:
      if textResolver.isNil:
        fail("text resolver required")
      fig = Fig(
        kind: nkText,
        screenBox: n.bounds,
        fill: fill(n.textColor),
        textLayout: textResolver(n.fontId, n.text, n.bounds, n.textColor),
      )
    of snImage:
      if imageResolver.isNil:
        fail("image resolver required")
      fig = Fig(
        kind: nkImage, screenBox: n.bounds, image: imageStyle(imageResolver(n.imageId))
      )
    if n.parent == -1:
      discard result.addRoot(fig)
    else:
      discard result.addChild(n.parent.FigIdx, fig)
