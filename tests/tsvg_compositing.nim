import std/unittest
import pkg/pixie
import figdraw/svgs/[svgpathloader, svgraster, svg]
import figdraw/figrender
import figdraw/software/context

suite "SVG raster compositing":
  test "opacity groups retain native primitives and isolate raster effects":
    let resource = newSvgMtsdfResource(
      """
<svg viewBox='0 0 64 64'><defs><mask id='m' mask-type='alpha'>
<rect width='64' height='64' fill='white' opacity='.5'/></mask></defs>
<g opacity='.5'><rect width='32' height='32' fill='red'/>
<g opacity='.5'><g mask='url(#m)'><rect x='32' width='32' height='32' fill='blue'/>
</g></g></g><rect y='32' width='64' height='32' fill='lime'/></svg>
"""
    )
    var kinds: seq[SvgLayerKind]
    for layer in resource.layers:
      kinds.add layer.kind
    check kinds ==
      @[
        slkGroupStart, slkRectangle, slkGroupStart, slkRasterGroup, slkGroupEnd,
        slkGroupEnd, slkRectangle,
      ]
    check resource.elementCount == 3
    var list: RenderList
    let parent = list.addRoot(Fig(kind: nkFrame))
    list.addSvgMtsdf(rect(0, 0, 64, 64), resource, parent = parent)
    check list.rootIds == @[parent]
    check list.nodes[0].childCount == 2
    check list.nodes[1].kind == nkOpacityGroup
    check list.nodes[1].opacity == 0.5
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64, 64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[8, 8].a in 126'u8 .. 129'u8
    check image[40, 8].a in 30'u8 .. 34'u8
    check image[40, 8].b == image[40, 8].a
    check image[8, 40].g == 255

  test "raster subgroups leave enclosing opacity open for later siblings":
    let resource = newSvgMtsdfResource(
      """
<svg viewBox='0 0 64 64'><defs><mask id='m' mask-type='alpha'>
<rect width='64' height='64' fill='white' opacity='.5'/></mask>
<linearGradient id='g'><stop stop-color='red'/><stop offset='1' stop-color='blue'/>
</linearGradient></defs><g opacity='.5'><g mask='url(#m)'>
<rect width='32' height='16'/><rect y='16' width='32' height='16'/></g>
<rect x='32' width='32' height='32' fill='url(#g)'/>
<rect y='32' width='64' height='32' fill='lime'/></g></svg>
"""
    )
    var kinds: seq[SvgLayerKind]
    for layer in resource.layers:
      kinds.add layer.kind
    check kinds ==
      @[slkGroupStart, slkRasterGroup, slkRasterGroup, slkRectangle, slkGroupEnd]
    var list: RenderList
    list.addSvgMtsdf(rect(0, 0, 64, 64), resource, fill(rgba(255, 0, 0, 255)))
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64, 64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[8, 8].a in 62'u8 .. 65'u8
    check image[40, 8].a in 126'u8 .. 129'u8
    check image[8, 40].a in 126'u8 .. 129'u8
    check image[8, 40].r == image[8, 40].a
    check image[8, 40].g == 0

  test "group opacity applies once to overlapping shapes":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><g opacity='.5'>
<rect width='8' height='8' fill='red'/><rect x='2' width='8' height='8' fill='blue'/>
</g></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 1, 100)
    check output.image[10, 10].a in 126'u8 .. 129'u8
    check output.image[40, 10].a in 126'u8 .. 129'u8
    check output.image[40, 10].b > 120
    check output.tintImage[40, 10].a in 126'u8 .. 129'u8
    check output.tintImage[40, 10].r == output.tintImage[40, 10].a

  test "linear gradients preserve colors and tint alpha":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><defs><linearGradient id='g'>
<stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue' stop-opacity='.5'/>
</linearGradient></defs><rect width='10' height='10' fill='url(#g)'/></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 0, 100)
    check output.image[10, 50].r > output.image[10, 50].b
    check output.image[90, 50].b > output.image[90, 50].r
    check output.tintImage[90, 50].a < output.tintImage[10, 50].a

  test "clips using referenced geometric paths":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><defs><clipPath id='c'><rect width='5' height='5'/></clipPath></defs>
<rect width='10' height='10' clip-path='url(#c)'/></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 0, 100)
    check output.image[20, 20].a == 255
    check output.image[80, 80].a == 0

  test "applies luminance masks to paint and tint":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><defs><mask id='m'>
<rect width='5' height='10' fill='white'/><rect x='5' width='5' height='10' fill='black'/>
</mask></defs><rect width='10' height='10' fill='red' mask='url(#m)'/></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 0, 100)
    check output.image[20, 20].a == 255
    check output.image[80, 20].a == 0
    check output.tintImage[80, 20].a == 0

  test "maps object bounding box clip coordinates":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 20 20'><defs><clipPath id='c' clipPathUnits='objectBoundingBox'>
<rect width='.5' height='1'/></clipPath></defs>
<rect x='4' y='2' width='8' height='10' fill='red' clip-path='url(#c)'/></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 0, 100)
    check output.image[30, 25].a == 255
    check output.image[50, 25].a == 0

  test "applies a translucent group mask once over overlapping children":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><defs><mask id='m' mask-type='alpha'>
<rect width='10' height='10' fill='white' opacity='.5'/></mask></defs>
<g mask='url(#m)'><rect width='8' height='8' fill='red'/>
<rect x='2' width='8' height='8' fill='blue'/></g></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 1, 100)
    check output.image[10, 10].a in 126'u8 .. 129'u8
    check output.image[40, 10].a in 126'u8 .. 129'u8
    check output.tintImage[40, 10].a in 126'u8 .. 129'u8

  test "nests group opacity and mask boundaries":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><defs><mask id='m' mask-type='alpha'>
<rect width='10' height='10' fill='white' opacity='.5'/></mask></defs>
<g opacity='.5'><g mask='url(#m)'><rect width='10' height='10'/></g></g></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 0, 100)
    check output.image[50, 50].a in 62'u8 .. 65'u8

  test "user-space gradient percentages use the viewport":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 10 10'><defs><linearGradient id='g' gradientUnits='userSpaceOnUse'>
<stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/>
</linearGradient></defs><rect width='10' height='10' fill='url(#g)'/></svg>
"""
    )
    let output = rasterizeSvgElements(document, 0, 0, 100)
    check output.image[10, 50].r > output.image[10, 50].b
    check output.image[90, 50].b > output.image[90, 50].r

  test "routes gradients clip paths and group masks through the renderer":
    let data = """
<svg viewBox='0 0 64 64'><defs><linearGradient id='g'>
<stop offset='0' stop-color='red'/><stop offset='1' stop-color='blue'/></linearGradient>
<clipPath id='c'><rect width='48' height='64'/></clipPath>
<mask id='m' mask-type='alpha'><rect width='64' height='64' fill='white' opacity='.5'/></mask>
</defs><g clip-path='url(#c)' mask='url(#m)'><rect width='64' height='64' fill='url(#g)'/>
<rect x='16' y='16' width='16' height='16' fill='green'/></g></svg>
"""
    let resource = newSvgMtsdfResource(data, longEdge = 128)
    var list: RenderList
    discard list.addSvgMtsdf(rect(0, 0, 64, 64), resource)
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64, 64), clearColor = color(0, 0, 0, 0))
    let rendered = ctx.readPixels(rect(0, 0, 0, 0), false)
    check rendered[8, 8].a in 125'u8 .. 130'u8
    check rendered[24, 24].a in 125'u8 .. 130'u8
    check rendered[24, 24].g > rendered[24, 24].r
    check rendered[55, 20].a == 0

  test "rejects non-finite viewport dimensions":
    expect PixieError:
      discard parseSvgDocument("<svg viewBox='0 0 1e999 10'/>")
