import std/unittest
import pkg/pixie
import figdraw/svgs/svg
import figdraw/figrender
import figdraw/software/context

suite "SVG opaque stroke meshes":
  test "uses a mesh and caches a union field for translucent tint":
    let svg = newSvgMtsdfResource(
      """<svg viewBox="0 0 64 64"><path d="M10 20 L40 20 L40 50"
        fill="none" stroke="red" stroke-width="10" stroke-linejoin="round"/></svg>""",
      longEdge = 128,
    )
    check svg.layers[0].kind == slkStrokeMesh
    check svg.image.isNil
    var list: RenderList
    discard list.addSvgMtsdf(rect(0, 0, 64, 64), svg)
    check list.nodes[1].drawOps[0].kind == dkFilledQuad
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let opaque = ctx.readPixels(rect(0, 0, 0, 0), false)
    var minimum = 255'u8
    for y in 17 .. 22:
      for x in 13 .. 35:
        minimum = min(minimum, opaque[x, y].a)
    check minimum == 255
    var tinted: RenderList
    discard tinted.addSvgMtsdf(rect(0, 0, 64, 64), svg, fill(rgba(0, 0, 255, 128)))
    check tinted.nodes[0].kind == nkMtsdfImage
    let firstId = tinted.nodes[0].mtsdfImage.id
    var again: RenderList
    discard again.addSvgMtsdf(rect(0, 0, 64, 64), svg, fill(rgba(0, 0, 255, 128)))
    check again.nodes[0].mtsdfImage.id == firstId
    scene.setLayer(0.ZLevel, tinted)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    check image[40, 20].a <= 128
    check image[40, 20].a > 100
    check image[20, 20].a > 100

  test "round caps and dashed lines use a union field for translucent tint":
    for dashes in ["", "stroke-dasharray='12 2'"]:
      let svg = newSvgMtsdfResource(
        """<svg viewBox="0 0 64 64"><path d="M10 32 L54 32"
          fill="none" stroke="red" stroke-width="10" stroke-linecap="round" """ &
          dashes & "/></svg>",
        longEdge = 128,
      )
      check svg.layers[0].kind == slkStrokePath
      var list: RenderList
      discard list.addSvgMtsdf(rect(0, 0, 64, 64), svg, fill(rgba(0, 0, 255, 128)))
      check list.nodes[0].kind == nkMtsdfImage
      var scene = newRenders()
      scene.setLayer(0.ZLevel, list)
      let ctx = newSoftwareContext(workers = 1)
      newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
      let image = ctx.readPixels(rect(0, 0, 0, 0), false)
      for x in 0 ..< 64:
        check image[x, 32].a <= 128
      check image[12, 32].a > 100
      check image[10, 32].a > 100

  test "thin stroke coverage tiers retain cache identities and tint opacity":
    let svg = newSvgMtsdfResource(
      """<svg viewBox='0 0 64 64'>
      <path d='M8 32 L32 32 L56 32' fill='none' stroke='black' stroke-width='.4'/></svg>"""
    )
    var small, again, large, tinted: RenderList
    small.addSvgMtsdf(rect(0, 0, 64, 64), svg)
    large.addSvgMtsdf(rect(0, 0, 128, 128), svg)
    again.addSvgMtsdf(rect(0, 0, 64, 64), svg)
    tinted.addSvgMtsdf(rect(0, 0, 64, 64), svg, fill(rgba(0, 0, 255, 128)))
    check small.nodes[0].kind == nkImage
    check small.nodes[0].image.id == again.nodes[0].image.id
    check small.nodes[0].image.id == tinted.nodes[0].image.id
    check small.nodes[0].image.id != large.nodes[0].image.id
    # Building the larger list must not invalidate the original texture.
    var scene = newRenders()
    scene.setLayer(0.ZLevel, tinted)
    let ctx = newSoftwareContext(workers = 1)
    newFigRenderer(ctx).renderFrame(scene, vec2(64), clearColor = color(0, 0, 0, 0))
    let image = ctx.readPixels(rect(0, 0, 0, 0), false)
    for x in 10 .. 54:
      let alpha = image[x, 31].a.int + image[x, 32].a.int
      check abs(alpha - 51) <= 5
      check image[x, 32].b == image[x, 32].a
