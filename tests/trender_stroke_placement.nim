import std/[os, unittest]
import pkg/pixie
import figdraw/[fignodes, windyshim]
import figdraw/utils/drawprimitives
import ./opengl_test_utils

proc strokeScene(w, h: float32): Renders =
  result = newRenders()
  discard result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, w, h),
      fill: fill(rgba(255, 255, 255, 255)),
    ),
  )
  discard result.addRoot(
    0.ZLevel,
    figEllipse(
      rect(16, 28, 40, 24),
      fill(rgba(0, 0, 0, 0)),
      RenderStroke(weight: 8, fill: fill(rgba(255, 0, 0, 255))),
    ),
  )
  discard result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkDrawable,
      screenBox: rect(88, 28, 40, 24),
      drawStroke: RenderStroke(weight: 8, fill: fill(rgba(0, 0, 255, 255))),
      drawOps: @[drawableEllipse(vec2(20, 12), vec2(20, 12))],
    ),
  )
  discard result.addRoot(
    0.ZLevel,
    figCircle(
      rect(152, 20, 40, 40),
      fill(rgba(0, 0, 0, 0)),
      RenderStroke(
        weight: 8,
        fill:
          linear(rgba(255, 0, 0, 255), rgba(0, 255, 0, 255), rgba(0, 0, 255, 255), fgaX),
      ),
    ),
  )

proc sample(image: Image, x, y: int): ColorRGBX =
  image[
    min(image.width - 1, x * image.width div 220),
    min(image.height - 1, y * image.height div 96),
  ]

suite "GPU stroke placement":
  test "prepared centered bands preserve inset and gradient rendering":
    block renderOnce:
      var image: Image
      try:
        image = renderAndScreenshotOnce(
          strokeScene,
          ensureTestOutputDir() / "render_stroke_placement.png",
          windowW = 220,
          windowH = 96,
          title = "figdraw stroke placement",
        )
      except WindyError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break renderOnce
      check image.sample(14, 40).r > 220
      check image.sample(14, 40).g < 30
      check image.sample(36, 40).g > 220
      check image.sample(14, 26).g > 220
      check image.sample(90, 30).r > 220
      check image.sample(86, 40).r > 220
      check image.sample(90, 40).b > 220
      check image.sample(90, 40).r < 30
      check image.sample(150, 40).r > 180
      check image.sample(172, 18).g > 180
      check image.sample(194, 40).b > 180
