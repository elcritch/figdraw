import std/[strutils, unittest]
import pkg/pixie
import figdraw/svgs/svg
import figdraw/figrender
import figdraw/software/context

proc document(body: string, attrs = ""): string =
  "<svg viewBox='0 0 64 64' " & attrs & ">" & body & "</svg>"

proc render(data: string): Image =
  let resource = newSvgMtsdfResource(data, longEdge = 128)
  var list: RenderList
  discard list.addSvgMtsdf(rect(0, 0, 64, 64), resource)
  var scene = newRenders()
  scene.setLayer(0.ZLevel, list)
  let ctx = newSoftwareContext(workers = 1)
  newFigRenderer(ctx).renderFrame(scene, vec2(64, 64), clearColor = color(0, 0, 0, 0))
  ctx.readPixels(rect(0, 0, 0, 0), false)

suite "SVG rendering regressions":
  test "line joins and dash gaps retain their geometry":
    let path =
      "<path d='M10 40 L30 40 L30 10' fill='none' stroke='red' " &
      "stroke-width='10' stroke-linejoin='$1'/>"
    let miter = render(document(path % "miter"))
    let bevel = render(document(path % "bevel"))
    let round = render(document(path % "round"))
    check miter[33, 43].a > 230
    check bevel[33, 43].a < 40
    check miter.data != round.data
    let dashed = render(
      document(
        "<line x1='8' y1='32' x2='56' y2='32' " &
          "stroke='red' stroke-width='4' stroke-dasharray='8 8'/>"
      )
    )
    check dashed[12, 32].a > 230
    check dashed[20, 32].a == 0
    check dashed[28, 32].a > 230

  test "translucent stroke joins and caps are composited once":
    let image = render(
      document(
        "<path d='M10 40 L30 40 L30 10' fill='none' " &
          "stroke='red' stroke-opacity='.5' stroke-width='10' " &
          "stroke-linecap='round' stroke-linejoin='round'/>"
      )
    )
    check abs(image[20, 40].a.int - 128) <= 3
    check abs(image[30, 40].a.int - 128) <= 3
    check abs(image[8, 40].a.int - 128) <= 3

  test "group opacity applies after overlapping children are combined":
    let image = render(
      document(
        "<g opacity='.5'><rect x='8' y='8' width='32' " &
          "height='32' fill='red'/><rect x='24' y='24' width='32' height='32' " &
          "fill='red'/></g>"
      )
    )
    check abs(image[16, 16].a.int - 128) <= 3
    check abs(image[32, 32].a.int - 128) <= 3

  test "styles currentColor RGB and explicit no stroke":
    let image = render(
      document(
        "<circle cx='16' cy='16' r='8' " &
          "style='fill:currentColor;fill-opacity:.5'/><rect x='32' y='8' " &
          "width='16' height='16' fill='rgb(0,255,0)' stroke='none' stroke-width='6'/>",
        "color='red'",
      )
    )
    check image[16, 16].r >= 126
    check abs(image[16, 16].a.int - 128) <= 3
    check image[40, 16].g == 255
    check image[30, 16].a == 0

  test "zero area elements and fractional viewBoxless dimensions":
    let image = render(
      "<svg width='64.5' height='64.5'><rect width='0' height='10'/>" &
        "<circle cx='32' cy='32' r='10' fill='blue'/></svg>"
    )
    check image[32, 32].b == 255
    check image[0, 5].a == 0
