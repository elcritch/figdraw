when defined(emscripten):
  import std/times
else:
  import std/[os, times]

import std/math
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

proc centeredRect(center, size: Vec2): Rect =
  rect(center.x - size.x / 2.0'f32, center.y - size.y / 2.0'f32, size.x, size.y)

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

proc makeRenderTree*(w, h: float32, pxRange: float32, t: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(30, 30, 30, 255).color,
  ))

  let margin = 40.0'f32
  let innerW = max(0.0'f32, w - margin * 2.0'f32)
  let innerH = max(0.0'f32, h - margin * 2.0'f32)
  let panelRect = rect(margin, margin, innerW, innerH)

  let gap = 28.0'f32
  let shadowOffset = vec2(18.0'f32, 18.0'f32)

  let leftW = innerW * 0.58'f32
  let rightW = innerW - leftW
  let leftRect = rect(panelRect.x, panelRect.y, leftW, innerH)
  let rightRect = rect(panelRect.x + leftW, panelRect.y, rightW, innerH)

  let bigBase = min(leftRect.w, leftRect.h) * 0.82'f32
  let bigBaseSize = vec2(bigBase, bigBase)
  let bigCenter = leftRect.xy + leftRect.wh / 2.0'f32
  let bigScale = 0.85'f32 + 0.20'f32 * (0.5'f32 + 0.5'f32 * sin(t * 1.6'f32))
  let bigSize = bigBaseSize * bigScale
  let bigRotation = t * 45.0'f32

  let smallBase = min((rightRect.w - gap) / 2.0'f32, rightRect.h * 0.45'f32)
  let smallBaseSize = vec2(smallBase, smallBase)
  let smallRowY = rightRect.y + smallBase / 2.0'f32 + rightRect.h * 0.05'f32
  let smallLeftCenter = vec2(rightRect.x + smallBase / 2.0'f32, smallRowY)
  let smallRightCenter =
    vec2(rightRect.x + smallBase * 1.5'f32 + gap, smallRowY)
  let smallScaleA = 0.80'f32 + 0.25'f32 * (0.5'f32 + 0.5'f32 * sin(t * 2.3'f32))
  let smallScaleB =
    0.80'f32 + 0.25'f32 * (0.5'f32 + 0.5'f32 * sin(t * 2.3'f32 + PI.float32))
  let smallRotationA = -t * 90.0'f32
  let smallRotationB = t * 75.0'f32

  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: panelRect,
    fill: rgba(80, 80, 80, 255).color,
    corners: [16.0'f32, 16.0, 16.0, 16.0],
  ))

  ## MSDF star: shadow via MTSDF alpha, then solid fill via MSDF median.
  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: centeredRect(bigCenter + shadowOffset, bigSize),
    rotation: bigRotation,
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
    screenBox: centeredRect(bigCenter, bigSize),
    rotation: bigRotation,
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
    screenBox: centeredRect(smallLeftCenter, smallBaseSize * smallScaleA),
    rotation: smallRotationA,
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
    screenBox: centeredRect(smallRightCenter, smallBaseSize * smallScaleB),
    rotation: smallRotationB,
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
    box: rect(0, 0, 1024, 640),
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
  let animStart = epochTime()

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = 2048,
    pixelScale = app.pixelScale,
  )

  proc redraw() =
    let winInfo = window.getWindowInfo()
    let t = (epochTime() - animStart).float32
    var renders =
      makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h),
          renderPxRange, t)
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
