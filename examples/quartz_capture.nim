## Render a small FigDraw scene to a PNG without creating a window.
##
## Build/run:
##   nim r -d:figdraw.quartz=on examples/quartz_capture.nim --output=quartz.png

when not defined(macosx):
  {.error: "This example requires macOS".}

import std/[cmdline, strutils]

import pkg/chroma

import figdraw

proc outputPath(): string =
  result = "quartz-capture.png"
  for arg in commandLineParams():
    if arg.startsWith("--output="):
      result = arg[9 .. ^1]
    elif arg == "--help":
      echo "Usage: quartz_capture [--output=FILE]"
      quit(0)

proc makeScene(width, height: float32): Renders =
  result = newRenders()
  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, width, height),
      fill: rgba(248, 249, 252, 255),
    ),
  )

  discard result.addChild(
    0.ZLevel,
    root,
    Fig(
      kind: nkRectangle,
      screenBox: rect(24, 24, 180, 100),
      corners: [18'u16, 30'u16, 10'u16, 24'u16],
      cornerRadiiY: [10'u16, 24'u16, 18'u16, 34'u16],
      flags: {NfEllipticalCorners},
      fill: rgba(214, 63, 78, 255),
      stroke: RenderStroke(weight: 3, fill: rgba(100, 20, 30, 255)),
    ),
  )

  discard result.addChild(
    0.ZLevel,
    root,
    Fig(
      kind: nkRectangle,
      screenBox: rect(236, 24, 90, 90),
      corners: [45'u16, 45'u16, 45'u16, 45'u16],
      fill: rgba(43, 124, 214, 255),
    ),
  )

  discard result.addChild(
    0.ZLevel,
    root,
    Fig(
      kind: nkDrawable,
      screenBox: rect(24, 156, 302, 110),
      fill: fill(rgba(0, 0, 0, 0)),
      drawStroke: RenderStroke(weight: 5, fill: rgba(35, 48, 74, 255), cap: scRound),
      drawOps:
        @[
          drawableEllipse(vec2(64, 54), vec2(52, 32)),
          drawableLine(vec2(130, 90), vec2(180, 18)),
          drawableBezier(@[vec2(176, 88), vec2(218, 4), vec2(286, 64)]),
        ],
    ),
  )

let width = 350'f32
let height = 290'f32
let renderer = newFigRenderer(atlasSize = 64)
var renders = makeScene(width, height)
renderer.renderFrame(
  renders, vec2(width, height), clearColor = rgba(248, 249, 252, 255).color
)
let output = outputPath()
renderer.takeOneFrameScreenshot().writeFile(output)
echo "Wrote ", output
