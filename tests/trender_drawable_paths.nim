import std/[math, os, unittest]

import pkg/pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/windowing/windyshim

import ./opengl_test_utils

proc makePathRenderTree(w, h: float32): Renders =
  var list = RenderList()
  let root = list.addRoot(
    Fig(
      kind: nkRectangle,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 255),
    )
  )

  discard list.addChild(
    root,
    Fig(
      kind: nkDrawable,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(220, 40, 40, 255),
      drawOps:
        @[
          drawablePath(
            [
              initDrawableContour(
                [
                  drawablePathLine(40, 140, 40, 60),
                  drawablePathBezier(
                    vec2(40.0'f32, 60.0'f32),
                    vec2(120.0'f32, 10.0'f32),
                    vec2(200.0'f32, 60.0'f32),
                  ),
                  drawablePathLine(200, 60, 200, 140),
                  drawablePathLine(200, 140, 40, 140),
                ]
              ),
              initDrawableContour(
                [
                  drawablePathArc(
                    vec2(120.0'f32, 90.0'f32), 22.0'f32, 0.0'f32, PI.float32 * 2.0'f32
                  )
                ]
              ),
            ],
            dfrEvenOdd,
          )
        ],
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "drawable path render":
  test "renders an even odd path through the preferred backend":
    let
      outDir = ensureTestOutputDir()
      outPath = outDir / "render_drawable_path.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var image: Image
      try:
        image = renderAndScreenshotOnce(
          makeRenders = makePathRenderTree,
          outputPath = outPath,
          windowW = 240,
          windowH = 180,
          title = "figdraw test: drawable path",
        )
      except WindyError:
        if getEnv("FIGDRAW_REQUIRE_GRAPHICS") == "1":
          raise
        skip()
        break renderOnce

      check fileExists(outPath)
      let
        filled = image[60, 100]
        hole = image[120, 90]
        outside = image[20, 20]
      check filled.r > 180'u8
      check filled.g < 90'u8
      check filled.b < 90'u8
      check hole.r > 230'u8
      check hole.g > 230'u8
      check hole.b > 230'u8
      check outside.r > 230'u8
      check outside.g > 230'u8
      check outside.b > 230'u8

      when UseMetalBackend:
        if getEnv("FIGDRAW_FORCE_OPENGL") != "1":
          var hasQuadraticFringePixel = false
          for y in 25 ..< 58:
            for x in 50 ..< 190:
              let pixel = image[x, y]
              if pixel.r > 220'u8 and pixel.r < 255'u8 and pixel.g > 40'u8 and
                  pixel.g < 255'u8 and pixel.b > 40'u8 and pixel.b < 255'u8:
                hasQuadraticFringePixel = true
          check hasQuadraticFringePixel
