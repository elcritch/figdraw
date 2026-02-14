import std/times
import std/strutils
when not defined(emscripten):
  import std/os
import chroma

import figdraw/windowing/siwinshim

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
        flags:
          if clip:
            {NfClipContent}
          else:
            {},
      ),
    )

  proc addRootRect(
      list: var RenderList, rectBox: Rect, color: Color, z: ZLevel, clip: bool = false
  ): FigIdx =
    list.addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: z,
        screenBox: rectBox,
        fill: color,
        corners: [10.0'f32, 10.0, 10.0, 10.0],
        flags:
          if clip:
            {NfClipContent}
          else:
            {},
      )
    )

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

  var layer0List = RenderList()
  let leftContainer = addRootRect(
    layer0List,
    rect(containerLeftX, containerY, containerW, containerH),
    containerColor,
    0.ZLevel,
  )
  let rightContainer = addRootRect(
    layer0List,
    rect(containerRightX, containerY, containerW, containerH),
    containerColor,
    0.ZLevel,
    clip = true,
  )

  addRect(
    layer0List,
    leftContainer,
    rect(containerLeftX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )
  addRect(
    layer0List,
    rightContainer,
    rect(containerRightX + buttonX, containerY + buttonY2, buttonW, buttonH),
    buttonColor,
    0.ZLevel,
  )

  var lowList = RenderList()
  var topList = RenderList()

  discard addRootRect(
    lowList,
    rect(containerLeftX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  discard addRootRect(
    topList,
    rect(containerLeftX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  discard addRootRect(
    lowList,
    rect(containerRightX + buttonX, containerY + buttonY3, buttonW, buttonH),
    buttonColor,
    (-5).ZLevel,
  )
  discard addRootRect(
    topList,
    rect(containerRightX + buttonX, containerY + buttonY1, buttonW, buttonH),
    buttonColor,
    20.ZLevel,
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[(-20).ZLevel] = bgList
  result.layers[0.ZLevel] = layer0List
  result.layers[(-5).ZLevel] = lowList
  result.layers[20.ZLevel] = topList
  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

when isMainModule:
  var appRunning = true

  let title = siwinWindowTitle("Siwin Layers + Clip")
  let size = ivec2(800, 375)
  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  when UseVulkanBackend:
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = size, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()

  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin Layers + Clip")

  var renders = makeRenderTree(0.0'f32, 0.0'f32)
  var lastSize = vec2(0.0'f32, 0.0'f32)

  proc redraw() =
    renderer.beginFrame()
    let sz = appWindow.logicalSize()
    if sz != lastSize:
      lastSize = sz
      renders = makeRenderTree(sz.x, sz.y)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      appRunning = false,
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
    while appRunning and appWindow.opened:
      appWindow.redraw()
      appWindow.step()

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
      appWindow.close()
