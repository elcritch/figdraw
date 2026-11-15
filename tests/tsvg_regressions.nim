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

  test "raster mode preserves paint order, opacity, tint, and cache identity":
    let data = document(
      "<g opacity='.5'><rect x='4' y='4' width='40' height='40' fill='red'/>" &
        "<path d='M20 12 L52 12 L52 44 Z' fill='blue' stroke='green' stroke-width='4'/></g>"
    )
    let raster = newSvgMtsdfResource(data, longEdge = 128, renderMode = srmRaster)
    let vector = newSvgMtsdfResource(data, longEdge = 128)
    check raster.elementCount == vector.elementCount
    check raster.layers[0].kind == slkGroupStart
    for layer in raster.layers:
      check layer.kind in {slkGroupStart, slkGroupEnd, slkRasterGroup}
    var list: RenderList
    list.addSvgMtsdf(rect(0, 0, 64, 64), raster)
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[8, 8].r in 126'u8 .. 129'u8
    check image[40, 20].b in 126'u8 .. 129'u8
    check image[60, 60].a == 0
    var tinted: RenderList
    tinted.addSvgMtsdf(rect(0, 0, 64, 64), raster, fill(rgba(255, 255, 0, 255)))
    scene.setLayer(0.ZLevel, tinted)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let yellow = ctx.readPixels(rect(0, 0, 0, 0), false)
    check yellow[40, 20].r in 126'u8 .. 129'u8
    check yellow[40, 20].g in 126'u8 .. 129'u8
    check yellow[40, 20].b == 0
    let singlePath = document("<path d='M4 4 L60 4 L32 60 Z' fill='red'/>")
    let bitmapPath =
      newSvgMtsdfResource(singlePath, longEdge = 128, renderMode = srmRaster)
    let fieldPath = newSvgMtsdfResource(singlePath, longEdge = 128)
    check bitmapPath.layers[0].rasterImage.id != fieldPath.layers[0].image.id

  test "raster mode preserves masked groups and later siblings":
    let data = document(
      "<defs><clipPath id='c'><rect width='16' height='32'/></clipPath></defs>" &
        "<g opacity='.5'><g clip-path='url(#c)'><rect width='32' height='32' fill='red'/></g>" &
        "<rect x='32' width='32' height='32' fill='blue'/></g>"
    )
    let svg = newSvgMtsdfResource(data, longEdge = 128, renderMode = srmRaster)
    var list: RenderList
    list.addSvgMtsdf(rect(0, 0, 64, 64), svg)
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[8, 8].a in 126'u8 .. 129'u8
    check image[24, 8].a == 0
    check image[40, 8].b in 126'u8 .. 129'u8
