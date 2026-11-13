import std/[os, unittest]
import pkg/pixie
import figdraw/[fignodes, windyshim]
import ./opengl_test_utils

suite "GPU subpixel stroke geometry":
  test "thin mesh vertices retain fractional coordinates":
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
      list.addRoot(
        Fig(
          kind: nkDrawable,
          screenBox: rect(0, 0, w, h),
          fill: fill(rgba(0, 0, 0, 255)),
          drawOps: @[
            drawableFilledQuad(
              [vec2(8.2, 4.2), vec2(8.8, 4.2), vec2(8.8, 20.8), vec2(8.2, 20.8)]
            )
          ],
        )
      )
      result.setLayer(0.ZLevel, list)

    block renderOnce:
      var image: Image
      try:
        image = renderAndScreenshotOnce(
          scene, ensureTestOutputDir() / "svg_subpixel.png", windowW = 32, windowH = 32
        )
      except WindyError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break renderOnce
      let factor = image.width div 32
      check image[8 * factor + factor div 2, 12 * factor].r < 200
      check image[10 * factor, 12 * factor].r == 255
