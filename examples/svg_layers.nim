## Render an SVG on the GPU and save a screenshot of the frame.
## Run: nim r examples/svg_layers.nim [input.svg] [output.png] [longEdge] [adaptive|fixed]
import std/[os, strutils, monotimes, times]
import pixie
import figdraw/svgs/svg
import figdraw/figrender
import figdraw/commons

when not UseMetalBackend:
  import figdraw/windyshim

const FrameSize = 512

proc svgScene(resource: SvgMtsdfResource): Renders =
  result = newRenders()
  var list: RenderList
  list.addRoot(
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, FrameSize, FrameSize),
      fill: fill(rgba(255, 255, 255, 255)),
    )
  )
  list.addSvgMtsdf(rect(16, 16, FrameSize - 32, FrameSize - 32), resource)
  result.setLayer(0.ZLevel, list)

proc renderScreenshot(resource: SvgMtsdfResource, output: string) =
  var scene = svgScene(resource)
  when UseMetalBackend:
    # Metal renders directly into an offscreen GPU target without a window.
    let renderer = newFigRenderer(atlasSize = 2048)
    renderer.renderFrame(scene, vec2(FrameSize.float32))
    renderer.takeOneFrameScreenshot().writeFile(output)
    echo "Wrote ", output, " (", renderer.backendName(), ")"
  else:
    # OpenGL needs a current context; Vulkan uses the window's presentation target.
    let window = newWindyWindow(
      size = ivec2(FrameSize, FrameSize),
      fullscreen = false,
      title = "FigDraw SVG GPU screenshot",
    )
    try:
      let renderer =
        newFigRenderer(atlasSize = 2048, backendState = WindyRenderBackend())
      renderer.setupBackend(window)
      pollEvents()
      renderer.beginFrame()
      renderer.renderFrame(scene, vec2(FrameSize.float32))
      var screenshot: Image
      if renderer.backendKind() == rbOpenGL:
        screenshot = renderer.takeOneFrameScreenshot()
        renderer.endFrame()
      else:
        renderer.endFrame()
        screenshot = renderer.takeOneFrameScreenshot()
      screenshot.writeFile(output)
      renderer.finishPendingFrames()
      echo "Wrote ", output, " (", renderer.backendName(), ")"
    finally:
      window.close()

let
  input =
    if paramCount() > 0:
      paramStr(1)
    else:
      "data/Ghostscript_Tiger.svg"
  output =
    if paramCount() > 1:
      paramStr(2)
    else:
      "svg_layers.png"
  longEdge =
    if paramCount() > 2:
      parseInt(paramStr(3))
    else:
      DefaultSvgMtsdfLongEdge
  adaptive = paramCount() < 4 or paramStr(4) != "fixed"
  start = getMonoTime()
  resource =
    newSvgMtsdfResourceFromFile(input, longEdge = longEdge, adaptive = adaptive)
let loaded = getMonoTime()
echo "Load ms: ", (loaded - start).inMilliseconds
renderScreenshot(resource, output)
echo "Scene and capture ms: ", (getMonoTime() - loaded).inMilliseconds
