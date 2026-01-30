when defined(emscripten):
  import std/times
else:
  import std/[os, times]

import chroma
import pkg/sdfy
import pkg/sdfy/msdfgenSvg

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc setupWindow(frame: AppFrame, window: Window) =
  when not defined(emscripten):
    if frame.windowInfo.fullscreen:
      window.fullscreen = frame.windowInfo.fullscreen
    else:
      window.size = ivec2(frame.windowInfo.box.wh.scaled())

    window.visible = true
  window.makeContextCurrent()

proc newWindyWindow(frame: AppFrame): Window =
  let window = when defined(emscripten):
      newWindow("FigDraw", ivec2(0, 0), visible = false)
    else:
      newWindow("FigDraw", ivec2(1280, 800), visible = false)
  when defined(emscripten):
    setupWindow(frame, window)
    startOpenGL(openglVersion)
  else:
    startOpenGL(openglVersion)
    setupWindow(frame, window)
  result = window

proc getWindowInfo(window: Window): WindowInfo =
  app.requestedFrame.inc
  result.minimized = window.minimized()
  result.pixelRatio = window.contentScale()
  let size = window.size()
  result.box.w = size.x.float32.descaled()
  result.box.h = size.y.float32.descaled()

proc makeRenderTree*(w, h: float32, pxRange: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(30, 30, 30, 255).color,
  ))

  let starSize = vec2(320.0'f32, 320.0'f32)
  let shadowOffset = vec2(18.0'f32, 18.0'f32)

  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(40, 40, 520, 520),
    fill: rgba(80, 80, 80, 255).color,
    corners: [16.0'f32, 16.0, 16.0, 16.0],
  ))

  ## MSDF star: shadow via MTSDF alpha, then solid fill via MSDF median.
  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(100 + shadowOffset.x, 100 + shadowOffset.y, starSize.x,
        starSize.y),
    image: ImageStyle(
      color: rgba(0, 0, 0, 140).color,
      id: imgId("star-mtsdf"),
      mode: irmMtsdf,
      msdfPxRange: pxRange,
    ),
  ))
  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(100, 100, starSize.x, starSize.y),
    image: ImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-msdf"),
      mode: irmMsdf,
      msdfPxRange: pxRange,
    ),
  ))

  ## Side-by-side comparison: same bitmap, different render mode.
  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(520, 120, 180, 180),
    image: ImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-msdf"),
      mode: irmMsdf,
      msdfPxRange: pxRange,
    ),
  ))
  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(720, 120, 180, 180),
    image: ImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-mtsdf"),
      mode: irmMtsdf,
      msdfPxRange: pxRange,
    ),
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  let svgPath = figDataDir() / "Yellow_Star_with_rounded_edges.svg"
  let (starPath, elementCount) = loadSvgPath(svgPath)
  doAssert elementCount > 0

  let fieldSize = 64
  let pxRange = 4.0
  let starMsdf = generateMsdfPath(starPath, fieldSize, fieldSize, pxRange)
  let starMtsdf = generateMtsdfPath(starPath, fieldSize, fieldSize, pxRange)
  let renderPxRange = (starMsdf.range * starMsdf.scale).float32

  loadImage(imgId("star-msdf"), starMsdf.image)
  loadImage(imgId("star-mtsdf"), starMtsdf.image)

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  var frame = AppFrame(
    windowTitle: "figdraw: OpenGL + Windy MSDF/MTSDF",
  )
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, 980, 640),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  let window = newWindyWindow(frame)

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = 2048,
    pixelScale = app.pixelScale,
  )

  proc redraw() =
    let winInfo = window.getWindowInfo()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h), renderPxRange)
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    window.swapBuffers()

  window.onCloseRequest = proc() =
    app.running = false
  window.onResize = proc() =
    redraw()

  try:
    while app.running:
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
        app.running = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
