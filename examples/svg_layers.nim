## Render an SVG to PNG using ordered vector and MTSDF layers.
## Run: nim r examples/svg_layers.nim [input.svg] [output.png]
import std/os
import pixie
import figdraw/svgs/svg
import figdraw/figrender
import figdraw/software/context

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
  resource = newSvgMtsdfResourceFromFile(input)
  ctx = newSoftwareContext()
  renderer = newFigRenderer(ctx)
var scene = newRenders()
var list: RenderList
list.addSvgMtsdf(rect(16, 16, 480, 480), resource)
scene.setLayer(0.ZLevel, list)
renderer.renderFrame(scene, vec2(512, 512), clearColor = color(1, 1, 1, 1))
ctx.readPixels(rect(0, 0, 0, 0), false).writeFile(output)
echo output
