when defined(emscripten):
  import std/[times, strutils]
else:
  import std/[os, times, strutils]
import chroma

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc makeRenderTree*(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(30, 30, 30, 255),
    )
  )

  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(40, 40, 320, 320),
      fill: rgba(80, 80, 80, 255),
      corners: [16.0'f32, 16.0, 16.0, 16.0],
    ),
  )

  list.addChild(
    rootIdx,
    Fig(
      kind: nkImage,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(60, 60, 280, 280),
      image: ImageStyle(color: rgba(255, 255, 255, 255).color, id: imgId("img1.png")),
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  discard loadImage("img1.png")

  var app_running = true

  let title = windyWindowTitle("Windy Image RenderList")
  let size = ivec2(800, 600)
  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  let window = newWindyWindow(size = size, fullscreen = false, title = title)

  if getEnv("HDI") != "":
    setFigUiScale getEnv("HDI").parseFloat()
  else:
    setFigUiScale window.contentScale()
  if size != size.scaled():
    window.size = size.scaled()

  let renderer =
    glrenderer.newFigRenderer(atlasSize = 2048, backendState = WindyRenderBackend())
  renderer.setupBackend(window)

  proc redraw() =
    renderer.beginFrame()
    let sz = window.logicalSize()
    var renders = makeRenderTree(sz.x, sz.y)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  window.onCloseRequest = proc() =
    app_running = false
  window.onResize = proc() =
    redraw()

  try:
    while app_running:
      pollEvents()
      redraw()

      inc frames
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        echo "fps: ", fps
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        app_running = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
