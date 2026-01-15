import std/[os, times, random, math, monotimes]
import chroma

import windex

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
var globalFrame = 0

proc setupWindow(frame: AppFrame, window: Window) =
  let style: WindowStyle = case frame.windowStyle
    of FrameStyle.DecoratedResizable: WindowStyle.DecoratedResizable
    of FrameStyle.DecoratedFixedSized: WindowStyle.Decorated
    of FrameStyle.Undecorated: WindowStyle.Undecorated
    of FrameStyle.Transparent: WindowStyle.Transparent

  if frame.windowInfo.fullscreen:
    window.fullscreen = frame.windowInfo.fullscreen
  else:
    window.size = ivec2(frame.windowInfo.box.wh.scaled())

  window.visible = true
  window.makeContextCurrent()

  let winCfg = frame.loadLastWindow()
  window.`style=`(style)
  window.`pos=`(winCfg.pos)

proc newWindyWindow(frame: AppFrame): Window =
  let window = newWindow("Figuro", ivec2(1280, 800), visible = false)
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

proc makeRenderTree*(w, h: float32): Renders =
  var list = RenderList()
  const copies = 400
  let t = globalFrame.float32 * 0.02'f32

  let rootId = 1.FigID
  list.nodes.add Fig(
    kind: nkRectangle,
    uid: rootId,
    parent: -1.FigID,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "root".toFigName(),
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 155).color,
  )

  list.rootIds = @[0.FigIdx]

  let maxX = max(0.0'f32, w - 220)
  let maxY = max(0.0'f32, h - 140)
  var rng = initRand((w.int shl 16) xor h.int xor 12345)

  for i in 0 ..< copies:
    let baseId = 2 + i * 3
    let baseX = rand(rng, 0.0'f32 .. maxX)
    let baseY = rand(rng, 0.0'f32 .. maxY)
    let jitterX = sin((t + i.float32 * 0.15'f32).float64).float32 * 20
    let jitterY = cos((t * 0.9'f32 + i.float32 * 0.2'f32).float64).float32 * 20
    let offsetX = min(max(baseX + jitterX, 0.0'f32), maxX)
    let offsetY = min(max(baseY + jitterY, 0.0'f32), maxY)

    let redIdx = list.nodes.len()
    list.nodes.add Fig(
      kind: nkRectangle,
      uid: FigID(baseId),
      parent: -1.FigID,
      childCount: 0,
      zlevel: 0.ZLevel,
      corners: [10.0'f32, 20.0, 30.0, 40.0],
      name: ("box-red-" & $i).toFigName(),
      screenBox: rect(60 + offsetX, 60 + offsetY, 220, 140),
      fill: rgba(220, 40, 40, 155).color,
      stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 155).color)
    )
    list.rootIds.add(redIdx.FigIdx)

    let greenIdx = list.nodes.len()
    list.nodes.add Fig(
      kind: nkRectangle,
      uid: FigID(baseId + 1),
      parent: -1.FigID,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: ("box-green-" & $i).toFigName(),
      screenBox: rect(320 + offsetX, 120 + offsetY, 220, 140),
      fill: rgba(40, 180, 90, 155).color,
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 10,
          spread: 10,
          x: 10,
          y: 10,
          color: rgba(0,0,0,155).color,
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ]
    )
    list.rootIds.add(greenIdx.FigIdx)

    let blueIdx = list.nodes.len()
    list.nodes.add Fig(
      kind: nkRectangle,
      uid: FigID(baseId + 2),
      parent: -1.FigID,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: ("box-blue-" & $i).toFigName(),
      screenBox: rect(180 + offsetX, 300 + offsetY, 220, 140),
      fill: rgba(60, 90, 220, 155).color,
    )
    list.rootIds.add(blueIdx.FigIdx)

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  var frame = AppFrame(
    windowTitle: "figdraw: OpenGL + Windy RenderList",
    windowStyle: FrameStyle.DecoratedResizable,
    configFile: getCurrentDir() / "examples" / "opengl_windy_renderlist",
    saveWindowState: false,
  )
  frame.windowInfo = WindowInfo(
    box: initBox(0, 0, 800, 600),
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
    atlasSize = 192,
    pixelScale = app.pixelScale,
  )

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0

  proc redraw() =
    let winInfo = window.getWindowInfo()

    let t0 = getMonoTime()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h))
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)

    let t1 = getMonoTime()
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    renderFrameMsSum += float((getMonoTime() - t1).inMilliseconds)

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
      inc globalFrame
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        let avgMake = makeRenderTreeMsSum / max(1, fpsFrames).float
        let avgRender = renderFrameMsSum / max(1, fpsFrames).float
        echo "fps: ", fps, " | makeRenderTree avg(ms): ", avgMake,
          " | renderFrame avg(ms): ", avgRender
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0
      if RunOnce and frames >= 1:
        app.running = false
      else:
        sleep(16)
  finally:
    window.close()
