# CBOR scene interchange, version 1

Install the optional dependency with `atlas --feature=cbor install` and import
`figdraw/scenecbor`. The core `figdraw` import does not import this module. Construct
`Scene` values, call `encodeScene` to obtain binary CBOR in a Nim string, and
call `decodeScene` to read it. `SceneWireError` reports invalid, unsupported,
or oversized scenes. `toRenderList` converts a scene into FigDraw nodes; pass a
`TextResolver` and/or `ImageResolver` when those node types occur.

```nim
import figdraw/[scenecbor, fignodes]

let scene = Scene(nodes: @[
  SceneNode(kind: snRectangle, bounds: rect(10, 20, 80, 40),
    color: rgba(255, 32, 16, 255))])
let bytes = scene.encodeScene()
let renderList = bytes.decodeScene().toRenderList()
```

The wire format is independent of Nim object layout and enum ordinals. A document
is a definite CBOR map in the fixed order `{0: 1, 1: nodes}`. Both keys are
required; other keys, duplicate keys, different order, other versions, tags,
indefinite lengths, and trailing data are rejected. `nodes` is a definite array
of records in parent-before-child order. The record shapes are:

| Code | Record |
| --- | --- |
| 0 | `[0, parent, x, y, width, height]` group |
| 1 | `[1, parent, x, y, width, height, rgba]` rectangle |
| 2 | `[2, parent, x, y, width, height, fontId, text, ?rgba]` text |
| 3 | `[3, parent, x, y, width, height, imageId]` image |

Parent is -1 for a root or a zero-based index of a preceding node. Sibling and
root order follow the array order. Bounds are finite float32 values in FigDraw
logical UI units; integers and CBOR floats are accepted and converted to
float32. The encoder uses integers for integral coordinates when compact and
CBOR floats otherwise. Color is an unsigned `0xRRGGBBAA` integer with straight,
not premultiplied, 8-bit channels. The optional final text color defaults to
opaque black (`0x000000ff`). Text is UTF-8. The document is limited to 16 MiB,
text to 1 MiB per node, and nodes to 32767. IDs are unsigned 64-bit values.

Resource IDs are application-defined identities, not addresses, FigDraw image
handles, fonts, glyph arrangements, or serialized resources. The receiver must
provide resource lookup and lifetime management. The image resolver maps an ID
to a local `ImageId`. The text resolver receives the font ID, text, bounds, and
color and must return a `GlyphArrangement` whose glyph fills reflect that color;
it is responsible for font selection, shaping, and layout. Unknown IDs should
raise from the resolver. No font size, shaping options, gradients, strokes,
shadows, clips, transforms, layers, or pre-shaped glyphs are represented in v1.
Use application-defined font IDs for all text styling needed by the resolver.
The bridge targets a single `RenderList`; the caller assigns its layer. There is
no implicit conversion from arbitrary `Fig` objects, so unsupported effects
cannot be silently discarded.
