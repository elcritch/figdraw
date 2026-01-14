import std/os
import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/openglWindex
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/baserenderer

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

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
    stroke: RenderStroke(weight: 5.0, color: rgba(0,0,0,255).color)
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
        color: blackColor,
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
    windowTitle: "figdraw: OpenGL + Windex RenderList",
    windowStyle: FrameStyle.DecoratedResizable,
    configFile: getCurrentDir() / "examples" / "opengl_windex_renderlist",
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

  let window = newWindexWindow(frame.addr)
  let renderer = glrenderer.newOpenGLRenderer(window, frame.addr,
      atlasSize = 2048)
  window.configureWindowEvents(renderer)

  try:
    var frames = 0
    while app.running:
      window.pollEvents()
      let winInfo = window.getWindowInfo()
      let renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h))
      renderer.setRenderState(renders, winInfo)
      renderer.renderAndSwap()

      inc frames
      if RunOnce and frames >= 1:
        app.running = false
      else:
        sleep(16)
  finally:
    window.closeWindow()
