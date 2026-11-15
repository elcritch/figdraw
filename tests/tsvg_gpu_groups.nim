import std/[os, unittest]
import pkg/pixie
import figdraw/[fignodes, windyshim]
import figdraw/svgs/svg
import ./opengl_test_utils

suite "SVG GPU opacity groups":
  test "native children overlap once and raster effects nest correctly":
    let resource = newSvgMtsdfResource(
      """
<svg viewBox='0 0 64 64'><defs><mask id='m' mask-type='alpha'>
<rect width='64' height='64' fill='white' opacity='.5'/></mask></defs>
<g opacity='.5'><rect x='4' y='4' width='32' height='24' fill='red'/>
<rect x='20' y='4' width='32' height='24' fill='blue'/>
<g opacity='.5'><rect x='4' y='36' width='16' height='16' fill='lime'/></g>
<g mask='url(#m)'><rect x='24' y='36' width='16' height='16' fill='red'/></g></g>
<rect x='56' y='4' width='8' height='8' fill='lime'/></svg>
"""
    )
    proc scene(w, h: float32): Renders =
      result = newRenders()
      var list: RenderList
      list.addRoot(
        Fig(
          kind: nkRectangle,
          screenBox: rect(0, 0, w, h),
          fill: fill(rgba(255, 255, 255, 255)),
        )
      )
      list.addSvgMtsdf(rect(0, 0, w, h), resource)
      result.setLayer(0.ZLevel, list)

    block renderOnce:
      var image: Image
      try:
        image = renderAndScreenshotOnce(
          scene,
          ensureTestOutputDir() / "svg_gpu_groups.png",
          windowW = 64,
          windowH = 64,
          title = "SVG GPU opacity groups",
        )
      except WindyError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break renderOnce

      template checkPixel(x, y, red, green, blue: int) =
        block:
          let pixel = image[x * image.width div 64, y * image.height div 64]
          check abs(pixel.r.int - red) <= 3
          check abs(pixel.g.int - green) <= 3
          check abs(pixel.b.int - blue) <= 3
          check pixel.a == 255

      checkPixel(8, 8, 255, 128, 128)
      checkPixel(24, 8, 128, 128, 255)
      checkPixel(48, 8, 128, 128, 255)
      checkPixel(8, 40, 191, 255, 191)
      checkPixel(28, 40, 255, 191, 191)
      checkPixel(60, 8, 0, 255, 0)
