import std/[os, times]
import chroma

import windex

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

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

  let rootId = 1.FigID
  list.nodes.add Fig(
    kind: nkRectangle,
    uid: rootId,
    parent: -1.FigID,
    childCount: 3,
    zlevel: 0.ZLevel,
    name: "root".toFigName(),
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 255).color,
  )

  list.rootIds = @[0.FigIdx]

  list.nodes.add Fig(
    kind: nkRectangle,
    uid: 2.FigID,
    parent: rootId,
    childCount: 0,
    zlevel: 0.ZLevel,
    corners: [10.0'f32, 20.0, 30.0, 40.0],
    name: "box-red".toFigName(),
    screenBox: rect(60, 60, 220, 140),
    fill: rgba(220, 40, 40, 255).color,
    stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 255).color)
  )
  list.nodes.add Fig(
    kind: nkRectangle,
    uid: 3.FigID,
    parent: rootId,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "box-green".toFigName(),
    screenBox: rect(320, 120, 220, 140),
    fill: rgba(40, 180, 90, 255).color,
    shadows: [
      RenderShadow(
        style: DropShadow,
        blur: 10,
        spread: 10,
        x: 10,
        y: 10,
        color: rgba(0,0,0,55).color,
    ),
    RenderShadow(),
    RenderShadow(),
    RenderShadow(),
  ]
  )
  list.nodes.add Fig(
    kind: nkRectangle,
    uid: 4.FigID,
    parent: rootId,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "box-blue".toFigName(),
    screenBox: rect(180, 300, 220, 140),
    fill: rgba(60, 90, 220, 255).color,
  )

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

  let winInfo = window.getWindowInfo()
  var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h))

  proc redraw() =
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
        sleep(16)
  finally:
    window.close()
