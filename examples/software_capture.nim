## atlas install --keepFeatures --feature=figdraw.uirelays
## nim r examples/software_capture.nim [output.png]
import std/os
import figdraw
import figdraw/software/context
import ./software_scene

let renderer = newFigRenderer(newSoftwareContext())
var scene: SoftwareSceneCache
var nodes = scene.softwareScene()
renderer.renderFrame(nodes, vec2(560, 360))
let output =
  if paramCount() > 0:
    paramStr(1)
  else:
    "software-capture.png"
renderer.takeOneFrameScreenshot().writeFile(output)
echo "Wrote ", output
