import std/times
import std/strutils
when not defined(emscripten):
  import std/os
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
  let bgColor = rgba(255, 255, 255, 255).color
  let containerColor = rgba(208, 208, 208, 255).color
  let buttonColor = rgba(43, 159, 234, 255).color

  let containerW = w * 0.30'f32
  let containerH = w * 0.40'f32
  let containerY = h * 0.10'f32
  let containerLeftX = w * 0.03'f32
  let containerRightX = w * 0.50'f32

  let buttonX = containerW * 0.10'f32
  let buttonW = containerW * 1.30'f32
  let buttonH = containerH * 0.20'f32
  let buttonY1 = containerH * 0.15'f32
  let buttonY2 = containerH * 0.45'f32
  let buttonY3 = containerH * 0.75'f32

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  discard result.addRoot(
    (-20).ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(0, 0, w, h),
      fill: bgColor,
    ),
  )

  let leftContainer = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerLeftX, containerY, containerW, containerH),
      fill: containerColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )
  let rightContainer = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerRightX, containerY, containerW, containerH),
      fill: containerColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
      flags: {NfClipContent},
    ),
  )

  discard result.addChild(
    0.ZLevel,
    leftContainer,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerLeftX + buttonX, containerY + buttonY2, buttonW, buttonH),
      fill: buttonColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )
  discard result.addChild(
    0.ZLevel,
    rightContainer,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerRightX + buttonX, containerY + buttonY2, buttonW, buttonH),
      fill: buttonColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )

  discard result.addRoot(
    (-5).ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerLeftX + buttonX, containerY + buttonY3, buttonW, buttonH),
      fill: buttonColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )
  discard result.addRoot(
    20.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerLeftX + buttonX, containerY + buttonY1, buttonW, buttonH),
      fill: buttonColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )

  discard result.addRoot(
    (-5).ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerRightX + buttonX, containerY + buttonY3, buttonW, buttonH),
      fill: buttonColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )
  discard result.addRoot(
    20.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(containerRightX + buttonX, containerY + buttonY1, buttonW, buttonH),
      fill: buttonColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    ),
  )

  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

when isMainModule:
  var appRunning = true

  let title = "figdraw: Windy Layers + Clip"
  let size = ivec2(800, 375)
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

  let renderer = glrenderer.newFigRenderer(atlasSize = 192)

  when UseMetalBackend:
    let metalHandle = attachMetalLayer(window, renderer.ctx.metalDevice())
    renderer.ctx.presentLayer = metalHandle.layer

  var renders = makeRenderTree(0.0'f32, 0.0'f32)
  var lastSize = vec2(0.0'f32, 0.0'f32)

  when UseMetalBackend:
    proc updateMetalLayer() =
      metalHandle.updateMetalLayer(window)

  proc redraw() =
    when UseMetalBackend:
      updateMetalLayer()
    let sz = window.logicalSize()
    if sz != lastSize:
      lastSize = sz
      renders = makeRenderTree(sz.x, sz.y)
    renderer.renderFrame(renders, sz)
    when not UseMetalBackend:
      window.swapBuffers()

  window.onCloseRequest = proc() =
    appRunning = false
  window.onResize = proc() =
    redraw()

  try:
    while appRunning:
      pollEvents()
      redraw()

      inc frames
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
