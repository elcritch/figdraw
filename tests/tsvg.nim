import std/[math, unittest]
import figdraw/svg

const mixedSvg = """
<svg viewBox="0 0 80 40">
  <g fill="#cc7226" stroke="#102030" stroke-width="2">
    <path d="M4 4 H36 V26 H4 Z" fill-opacity="0.5"/>
  </g>
  <circle cx="56" cy="20" r="8" fill="red" stroke="blue"/>
  <ellipse cx="70" cy="20" rx="6" ry="10" fill="green" stroke="black"/>
</svg>
"""

suite "SVG drawing layers":
  test "preserves ordered paints, vector primitives and shared ellipse fields":
    let svg = newSvgMtsdfResource(mixedSvg, longEdge = 64)
    check svg.size == vec2(80, 40)
    check svg.elementCount == 3
    check svg.len == 5
    check svg.layers[0].kind == slkMtsdfFill
    check svg.layers[0].paint.rgba == rgba(204, 114, 38, 128)
    check svg.layers[1].kind == slkStrokePath
    check svg.layers[1].paint.rgba == rgba(16, 32, 48, 255)
    check svg.layers[2].kind == slkCircle
    check svg.layers[3].kind == slkMtsdfFill
    check svg.layers[4].kind == slkMtsdfStroke
    check svg.layers[3].image == svg.layers[4].image
    check svg.image == svg.layers[0].image
    check abs(svg.pixelRange - 6) < 0.001

    var list: RenderList
    let last = list.addSvgMtsdf(rect(10, 20, 160, 80), svg)
    check last.int == 5
    check list.rootIds.len == 5
    check list.nodes[0].kind == nkMtsdfImage
    check list.nodes[0].mtsdfImage.fill.color == rgba(204, 114, 38, 128)
    check list.nodes[1].drawStroke.fill.color == rgba(16, 32, 48, 255)
    check list.nodes[1].drawStroke.weight == 4
    check list.nodes[2].kind == nkTransform
    check list.nodes[2].childCount == 1
    check list.nodes[2].transform.translation == vec2(122, 60)
    check list.nodes[3].parent == FigIdx(2)
    check list.nodes[3].drawOps[0].kind == dkCircle
    check list.nodes[5].mtsdfImage.strokeWeight == 2

  test "appends tinted layers under an existing parent":
    let svg = newSvgMtsdfResource(mixedSvg, longEdge = 32)
    var list: RenderList
    let parent = list.addRoot(Fig(kind: nkFrame))
    let tint = fill(rgba(10, 20, 30, 255))
    discard list.addSvgMtsdf(rect(0, 0, 80, 40), svg, tint, parent = parent)
    check list.rootIds == @[parent]
    check list.nodes[0].childCount == 5
    check list.nodes[1].mtsdfImage.fill == tint
    check list.nodes[2].drawStroke.fill == tint
    check list.nodes[4].fill == tint
    check list.nodes[4].drawStroke.fill == tint
    check list.nodes[5].mtsdfImage.fill == tint

  test "vector-only resources allocate no image":
    let svg = newSvgMtsdfResource(
      """
<svg viewBox="0 0 40 40">
  <path d="M2 3 L10 3 Q20 3 20 10 C20 20 30 20 30 30"
    fill="none" stroke="black" stroke-linecap="round"/>
</svg>
"""
    )
    check svg.len == 1
    check svg.image.isNil
    check svg.pixelRange == 0
    var list: RenderList
    discard list.addSvgMtsdf(rect(5, 7, 80, 80), svg)
    check list.nodes[0].drawOps.len == 3
    check list.nodes[0].drawOps[0].a == vec2(4, 6)
    check list.nodes[0].drawStroke.cap == scRound
    check list.nodes[0].drawOps[1].controls.len == 3
    check list.nodes[0].drawOps[2].controls.len == 4

  test "anonymous resources have distinct image identities":
    let a = newSvgMtsdfResource(
      "<svg viewBox=\"0 0 10 10\"><rect width=\"8\" height=\"8\"/></svg>"
    )
    let b = newSvgMtsdfResource(
      "<svg viewBox=\"0 0 10 10\"><circle r=\"4\"/><rect width=\"6\" height=\"6\"/></svg>"
    )
    check a.image.id != b.image.id

  test "empty resources leave render lists unchanged":
    var list: RenderList
    check list.addSvgMtsdf(rect(0, 0, 10, 10), SvgMtsdfResource()).int == -1
    check list.len == 0

  test "rejects malformed, invisible and unsupported documents":
    for data in [
      "not XML", "<svg viewBox=\"0 0 10 10\"></svg>",
      "<svg viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" display=\"none\"/></svg>",
      "<svg viewBox=\"0 0 10 10\"><rect width=\"10\" height=\"10\" fill=\"url(#gradient)\"/></svg>",
    ]:
      expect SvgMtsdfError:
        discard newSvgMtsdfResource(data)
    for pixelRange in [0.0, -1.0, Inf, NaN]:
      expect SvgMtsdfError:
        discard newSvgMtsdfResource(mixedSvg, pixelRange = pixelRange)
    expect SvgMtsdfError:
      discard newSvgMtsdfResource(mixedSvg, longEdge = 4, pixelRange = 6)

  test "loads files and translates missing-file errors":
    let svg = newSvgMtsdfResourceFromFile("data/Yellow_Star_with_rounded_edges.svg")
    check svg.len > 0
    expect SvgMtsdfError:
      discard newSvgMtsdfResourceFromFile("data/missing-svg-file.svg")
