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

proc addRect(
    list: var RenderList,
    parentIdx: FigIdx,
    rectBox: Rect,
    color: Color,
    z: ZLevel,
    clip: bool = false,
) =
  discard list.addChild(
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
      flags: if clip: {NfClipContent} else: {},
    ),
  )

proc addRootRect(
    list: var RenderList,
    rectBox: Rect,
    color: Color,
    z: ZLevel,
    clip: bool = false,
) : FigIdx =
  list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
      flags: if clip: {NfClipContent} else: {},
    )
  )

proc makeRenderTree*(w, h: float32): Renders =
  let bgColor = rgba(245, 245, 245, 255).color
  let containerColor = rgba(208, 208, 208, 255).color
  let buttonColor = rgba(0, 160, 255, 255).color
  let transparent = rgba(0, 0, 0, 0).color

  let containerW = w * 0.30'f32
  let containerH = h * 0.80'f32
  let containerY = h * 0.10'f32
  let containerLeftX = w * 0.03'f32
  let containerRightX = w * 0.50'f32

  let buttonX = containerW * 0.10'f32
  let buttonW = containerW * 1.30'f32
  let buttonH = containerH * 0.20'f32
  let buttonY1 = containerH * 0.15'f32
  let buttonY2 = containerH * 0.45'f32
  let buttonY3 = containerH * 0.75'f32

  var bgList = RenderList()
  discard bgList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-20).ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: bgColor,
    )
  )

  var containerList = RenderList()
  discard containerList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-10).ZLevel,
      screenBox: rect(containerLeftX, containerY, containerW, containerH),
      fill: containerColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    )
  )
  discard containerList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-10).ZLevel,
      screenBox: rect(containerRightX, containerY, containerW, containerH),
      fill: containerColor,
      corners: [10.0'f32, 10.0, 10.0, 10.0],
    )
  )

  var lowList = RenderList()
  var midList = RenderList()
  var topList = RenderList()

  discard addRootRect(
    lowList,
    rect(containerLeftX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  discard addRootRect(
    midList,
    rect(containerLeftX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )
  discard addRootRect(
    topList,
    rect(containerLeftX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  let rightLowClip = addRootRect(
    lowList,
    rect(containerRightX, containerY, containerW, containerH),
    transparent,
    (-5).ZLevel,
    clip = true,
  )
  let rightMidClip = addRootRect(
    midList,
    rect(containerRightX, containerY, containerW, containerH),
    transparent,
    0.ZLevel,
    clip = true,
  )
  let rightTopClip = addRootRect(
    topList,
    rect(containerRightX, containerY, containerW, containerH),
    transparent,
    20.ZLevel,
    clip = true,
  )

  addRect(
    lowList,
    rightLowClip,
    rect(containerRightX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  addRect(
    midList,
    rightMidClip,
    rect(containerRightX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )
  addRect(
    topList,
    rightTopClip,
    rect(containerRightX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[(-20).ZLevel] = bgList
  result.layers[(-10).ZLevel] = containerList
  result.layers[(-5).ZLevel] = lowList
  result.layers[0.ZLevel] = midList
  result.layers[20.ZLevel] = topList
  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

when isMainModule:
  var appRunning = true

  let title = "figdraw: Windy Layers + Clip"
  let size = ivec2(800, 400)
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
