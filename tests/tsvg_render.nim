import std/unittest
import pkg/pixie
import figdraw/svgs/svg
import figdraw/figrender
import figdraw/software/context

suite "SVG software rendering":
  test "renders ordered MTSDF fills, circles and line strokes at target scale":
    let svg = newSvgMtsdfResource(
      """
<svg viewBox="0 0 32 32">
  <path d="M4 4 H28 V28 H4 Z" fill="red"/>
  <circle cx="16" cy="16" r="6" fill="#00ff00"/>
  <line x1="2" y1="30" x2="30" y2="30" stroke="blue" stroke-width="2"/>
</svg>
""",
      longEdge = 64,
    )
    var list: RenderList
    discard list.addSvgMtsdf(rect(8, 8, 64, 64), svg)
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    let renderer = newFigRenderer(ctx)
    renderer.renderFrame(scene, vec2(80, 80), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[20, 20] == rgba(255, 0, 0, 255).rgbx
    check image[40, 40] == rgba(0, 255, 0, 255).rgbx
    check image[40, 68] == rgba(0, 0, 255, 255).rgbx
    check image[8, 8].a == 0

  test "retains even-odd holes in complex MTSDF fills":
    let svg = newSvgMtsdfResource(
      """
<svg viewBox="0 0 32 32">
  <path d="M2 2 H30 V30 H2 Z M10 10 H22 V22 H10 Z"
    fill="red" fill-rule="evenodd"/>
</svg>
""",
      longEdge = 64,
    )
    var list: RenderList
    discard list.addSvgMtsdf(rect(0, 0, 64, 64), svg)
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    let renderer = newFigRenderer(ctx)
    renderer.renderFrame(scene, vec2(64, 64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[12, 32].r == 255
    check image[32, 32].a == 0
    check image[0, 0].a == 0
