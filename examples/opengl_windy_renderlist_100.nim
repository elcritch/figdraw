import std/[os, times, monotimes]

when defined(useWindex):
  import windex
else:
  import windy

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

import renderlist_100_common

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
const NoSleep {.booldefine: "figdraw.noSleep".}: bool = true
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
    atlasSize = when not defined(useFigDrawTextures): 192 else: 2048,
    pixelScale = app.pixelScale,
  )

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0
  var lastElementCount = 0

  proc redraw() =
    let winInfo = window.getWindowInfo()

    let t0 = getMonoTime()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h),
      globalFrame)
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)
    lastElementCount = renders.layers[0.ZLevel].nodes.len

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
        echo "fps: ", fps, " | elems: ", lastElementCount,
          " | makeRenderTree avg(ms): ", avgMake, " | renderFrame avg(ms): ",
          avgRender
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0

      when RunOnce:
        if frames >= 1:
          app.running = false

      when not NoSleep:
        if app.running:
          sleep(16)
  finally:
    window.close()
