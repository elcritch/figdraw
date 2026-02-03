import std/[math, times]
import std/[strformat, strutils]
when not defined(emscripten):
  import std/os
import chroma

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/common/fonttypes
import figdraw/fignodes
import figdraw/figrender as glrenderer
import figdraw/lottie/loader
import figdraw/lottie/render

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

when isMainModule:
  var app_running = true

  let title = "figdraw: Windy Lottie Bouncy Ball"
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

  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  let typefaceId = loadTypeface("Ubuntu.ttf")
  let fpsFont = UiFont(typefaceId: typefaceId, size: 18.0'f32)
  var fpsText = "0.0 FPS"

  let anim = loadLottieFile(figDataDir() / "lottie" / "bouncy_ball.json")
  var lottieRenderer = initLottieMtsdfRenderer(anim)

  let renderer = glrenderer.newFigRenderer(atlasSize = 1024, )

  when UseMetalBackend:
    let metalHandle = attachMetalLayer(window, renderer.ctx.metalDevice())
    renderer.ctx.presentLayer = metalHandle.layer

  let startTime = epochTime()

  when UseMetalBackend:
    proc updateMetalLayer() =
      metalHandle.updateMetalLayer(window)

  proc redraw() =
    when UseMetalBackend:
      updateMetalLayer()
    let sz = window.logicalSize()
    let elapsed = epochTime() - startTime
    let frame = elapsed.float32 * anim.fr
    let loopLen = anim.op - anim.ip
    let loopFrame =
      if loopLen > 0.0'f32:
        let offset = frame - anim.ip
        offset - floor(offset / loopLen) * loopLen
      else:
        frame
    var renders = lottieRenderer.renderLottieFrame(loopFrame + anim.ip)

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
    renderer.renderFrame(renders, sz, clearColor = rgba(255, 255, 255, 255).color)
    when not UseMetalBackend:
      window.swapBuffers()

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
        fpsText = fmt"{fps:0.1f} FPS"
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        app_running = false
  finally:
    when not defined(emscripten):
      window.close()
