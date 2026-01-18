import std/[os, times]
import chroma

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
  let window = newWindow("FigDraw", ivec2(1280, 800), visible = false)
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
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "root".toFigName(),
    screenBox: rect(0, 0, w, h),
    fill: rgba(30, 30, 30, 255).color,
  )
  list.rootIds = @[0.FigIdx]

  list.addChild(0.FigIdx, Fig(
    kind: nkRectangle,
    uid: 2.FigID,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "img-bg".toFigName(),
    screenBox: rect(40, 40, 320, 320),
    fill: rgba(80, 80, 80, 255).color,
    corners: [16.0'f32, 16.0, 16.0, 16.0],
  ))

  list.addChild(0.FigIdx, Fig(
    kind: nkImage,
    uid: 3.FigID,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "img1".toFigName(),
    screenBox: rect(60, 60, 280, 280),
    image: ImageStyle(
      name: "img1.png".toFigName(),
      color: rgba(255, 255, 255, 255).color,
      id: hash("img1.png").ImageId,
    ),
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  setFigDataDir(getCurrentDir() / "data")

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  var frame = AppFrame(
    windowTitle: "figdraw: OpenGL + Windy image",
    windowStyle: FrameStyle.DecoratedResizable,
    configFile: getCurrentDir() / "examples" / "opengl_windy_image_renderlist",
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
    atlasSize = 2048,
    pixelScale = app.pixelScale,
  )

  proc redraw() =
    let winInfo = window.getWindowInfo()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h))
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
