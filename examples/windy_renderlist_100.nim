when defined(emscripten):
  import std/[times, monotimes, strformat]
else:
  import std/[os, times, monotimes, strformat]

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

import renderlist_100_common

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
const NoSleep {.booldefine: "figdraw.noSleep".}: bool = true
var globalFrame = 0

proc setupWindow(frame: AppFrame, window: Window) =
  when not defined(emscripten):
    if frame.windowInfo.fullscreen:
      window.fullscreen = frame.windowInfo.fullscreen
    else:
      window.size = ivec2(frame.windowInfo.box.wh.scaled())

    window.visible = true
  when not UseMetalBackend:
    window.makeContextCurrent()

proc newWindyWindow(frame: AppFrame): Window =
  let window =
    when defined(emscripten):
      newWindow("Figuro", ivec2(0, 0), visible = false)
    else:
      newWindow("Figuro", ivec2(1280, 800), visible = false)
  when defined(emscripten):
    setupWindow(frame, window)
    when not UseMetalBackend:
      startOpenGL(openglVersion)
  else:
    when not UseMetalBackend:
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
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  let typefaceId = getTypefaceImpl("Ubuntu.ttf")
  let fpsFont = UiFont(typefaceId: typefaceId, size: 18.0'f32, lineHeightScale: 1.0)
  var fpsText = "0.0 FPS"

  var frame = AppFrame(windowTitle: "figdraw: OpenGL + Windy RenderList")
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, 800, 600),
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

  let renderer = newFigRenderer(
    atlasSize = when not defined(useFigDrawTextures): 128 else: 2048,
    pixelScale = app.pixelScale,
  )

  when UseMetalBackend:
    let metalHandle = attachMetalLayer(window, renderer.ctx.metalDevice())
    renderer.ctx.presentLayer = metalHandle.layer

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0
  var lastElementCount = 0

  when UseMetalBackend:
    proc updateMetalLayer() =
      metalHandle.updateMetalLayer(window)

  proc redraw() =
    inc frames
    inc globalFrame
    inc fpsFrames

    when UseMetalBackend:
      updateMetalLayer()

    let winInfo = window.getWindowInfo()

    let t0 = getMonoTime()
    var renders =
      makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h), globalFrame)
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)
    lastElementCount = renders.layers[0.ZLevel].nodes.len

    let hudMargin = 12.0'f32
    let hudW = 180.0'f32
    let hudH = 34.0'f32
    let hudRect = rect(winInfo.box.w.float32 - hudW - hudMargin, hudMargin, hudW, hudH)

    discard renders.layers[0.ZLevel].addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: hudRect,
        fill: rgba(0, 0, 0, 155).color,
        corners: [8.0'f32, 8.0, 8.0, 8.0],
      )
    )

    let hudTextPadX = 10.0'f32
    let hudTextPadY = 6.0'f32
    let hudTextRect = rect(
      hudRect.x + hudTextPadX,
      hudRect.y + hudTextPadY,
      hudRect.w - hudTextPadX * 2,
      hudRect.h - hudTextPadY * 2,
    )

    let fpsLayout = typeset(
      rect(0, 0, hudTextRect.w, hudTextRect.h),
      [(fpsFont, fpsText)],
      hAlign = Right,
      vAlign = Middle,
      minContent = false,
      wrap = false,
    )

    discard renders.layers[0.ZLevel].addRoot(
      Fig(
        kind: nkText,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: hudTextRect,
        fill: rgba(255, 255, 255, 245).color,
        textLayout: fpsLayout,
      )
    )

    let t1 = getMonoTime()
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    renderFrameMsSum += float((getMonoTime() - t1).inMilliseconds)

    when not UseMetalBackend:
      window.swapBuffers()

  window.onCloseRequest = proc() =
    app.running = false
  window.onResize = proc() =
    redraw()

  try:
    while app.running:
      pollEvents()
      redraw()

      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        fpsText = fmt"{fps:0.1f} FPS"
        let avgMake = makeRenderTreeMsSum / max(1, fpsFrames).float
        let avgRender = renderFrameMsSum / max(1, fpsFrames).float
        echo "fps: ",
          fps, " | elems: ", lastElementCount, " | makeRenderTree avg(ms): ", avgMake,
          " | renderFrame avg(ms): ", avgRender
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0

      when RunOnce:
        if frames >= 1:
          app.running = false

      when not NoSleep and not defined(emscripten):
        if app.running:
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
