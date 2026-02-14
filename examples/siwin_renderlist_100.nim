when defined(emscripten):
  import std/[times, monotimes, strformat, strutils]
else:
  import std/[os, times, monotimes, strformat, strutils]

import figdraw/windowing/siwinshim

import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

import renderlist_100_common

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
const NoSleep {.booldefine: "figdraw.noSleep".}: bool = true
var globalFrame = 0

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var app_running = true

  let typefaceId = loadTypeface("Ubuntu.ttf")
  let fpsFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
  var fpsText = "0.0 FPS"

  let title = siwinWindowTitle("Siwin RenderList")
  let size = ivec2(800, 600)

  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
  let renderer = newFigRenderer(
    atlasSize = when not defined(useFigDrawTextures): 512 else: 2048,
    backendState = SiwinRenderBackend(),
  )
  let useAutoScale = appWindow.configureUiScale()
  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin RenderList")

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0
  var lastElementCount = 0

  proc redraw() =
    inc frames
    inc globalFrame
    inc fpsFrames

    renderer.beginFrame()
    let sz = appWindow.logicalSize()

    let t0 = getMonoTime()
    var renders = makeRenderTree(float32(sz.x), float32(sz.y), globalFrame)
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)
    lastElementCount = renders.layers[0.ZLevel].nodes.len

    let hudMargin = 12.0'f32
    let hudW = 180.0'f32
    let hudH = 34.0'f32
    let hudRect = rect(sz.x.float32 - hudW - hudMargin, hudMargin, hudW, hudH)

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
      [(fs(fpsFont, rgba(255, 255, 255, 245).color), fpsText)],
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
        fill: clearColor,
        textLayout: fpsLayout,
      )
    )

    let t1 = getMonoTime()
    renderer.renderFrame(renders, sz)
    renderFrameMsSum += float((getMonoTime() - t1).inMilliseconds)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      app_running = false,
    onResize: proc(e: ResizeEvent) =
      appWindow.refreshUiScale(useAutoScale)
      redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        close(e.window)
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  appWindow.firstStep()
  appWindow.refreshUiScale(useAutoScale)

  try:
    while app_running and appWindow.opened:
      appWindow.redraw()
      appWindow.step()

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
          app_running = false

      when not NoSleep and not defined(emscripten):
        if app_running:
          sleep(16)
  finally:
    when not defined(emscripten):
      appWindow.close()
