import std/[os, unittest]
import pkg/pixie
import figdraw/[fignodes, windyshim]
import ./opengl_test_utils
import figdraw/svgs/svg

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
      let factor = image.height div 32
      check image[8 * factor + factor div 2, 12 * factor].r < 200
      check image[10 * factor, 12 * factor].r == 255

  test "subpixel connected strokes have continuous partial coverage":
    let resource = newSvgMtsdfResource(
      """<svg viewBox='0 0 32 32'>
      <path d='M4 16.5 L16 16.5 L28 16.5' fill='none' stroke='black'
        stroke-width='.2'/></svg>"""
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
      list.addSvgMtsdf(rect(0.25, 0.25, 32, 32), resource)
      result.setLayer(0.ZLevel, list)

    block renderOnce:
      var image: Image
      try:
        image = renderAndScreenshotOnce(
          scene, ensureTestOutputDir() / "svg_hairline.png", windowW = 32, windowH = 32
        )
      except WindyError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break renderOnce
      let factor = image.height div 32
      for x in 6 .. 25:
        var darkness = 0
        for dy in 15 * factor ..< 19 * factor:
          for dx in x * factor ..< (x + 1) * factor:
            let red = image[dx, dy].r.int
            check red > 128 # No solid-black point samples.
            darkness += 255 - red
        check abs(darkness.float32 / (factor * factor).float32 - 51) < 12
      # Fractional placement must not be rounded to the next pixel row.
      if image.height == 32:
        check image[10, 16].r < 230

  test "fractional image placement preserves bilinear coverage":
    let pixels = newImage(4, 4)
    for x in 0 ..< 4:
      pixels[x, 1] = rgbx(128, 128, 128, 128)
    let texture = imageRef(imgId("svg-fractional-coverage-test"), pixels)
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
          kind: nkImage,
          screenBox: rect(8.25, 8.25, 4, 4),
          image: imageStyle(texture, fill(rgba(0, 0, 0, 255))),
        )
      )
      result.setLayer(0.ZLevel, list)

    block renderOnce:
      var image: Image
      try:
        image = renderAndScreenshotOnce(
          scene,
          ensureTestOutputDir() / "svg_fractional_image.png",
          windowW = 32,
          windowH = 32,
        )
      except WindyError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break renderOnce
      if image.height == 32:
        check image[10, 9].r in 150'u8 .. 170'u8
        check image[10, 10].r in 215'u8 .. 230'u8
