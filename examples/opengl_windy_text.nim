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

proc makeRenderTree*(w, h: float32, uiFont: UiFont): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(245, 245, 245, 255).color,
  ))

  let pad = 40'f32
  let cardRect = rect(pad, pad, w - pad * 2, h - pad * 2)
  let cardIdx = list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: cardRect,
    fill: rgba(255, 255, 255, 255).color,
    stroke: RenderStroke(weight: 2.0, color: rgba(0, 0, 0, 25).color),
    corners: [16.0'f32, 16.0, 16.0, 16.0],
    shadows: [
      RenderShadow(
        style: DropShadow,
        blur: 24,
        spread: 0,
        x: 0,
        y: 8,
        color: rgba(0, 0, 0, 30).color,
    ),
    RenderShadow(),
    RenderShadow(),
    RenderShadow(),
  ],
  ))

  let textPad = 28'f32
  let textRect = rect(
    cardRect.x + textPad,
    cardRect.y + textPad,
    cardRect.w - textPad * 2,
    cardRect.h - textPad * 2,
  )

  let text = """
FigDraw text demo

This example uses `src/figdraw/common/fontutils.nim` typesetting + glyph caching,
then renders glyph atlas sprites via the OpenGL renderer.
"""

  let layout = typeset(
    initBox(0, 0, textRect.w, textRect.h),
    [(uiFont, text)],
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
  )

  discard list.addChild(cardIdx, Fig(
    kind: nkText,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: textRect,
    fill: rgba(20, 20, 20, 255).color,
    textLayout: layout,
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  setFigDataDir(getCurrentDir() / "data")

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  let typefaceId = getTypefaceImpl("Ubuntu.ttf")
  let uiFont = UiFont(typefaceId: typefaceId, size: 28.0'ui,
      lineHeightScale: 0.9)

  var frame = AppFrame(
    windowTitle: "figdraw: OpenGL + Windy Text",
    windowStyle: FrameStyle.DecoratedResizable,
    configFile: getCurrentDir() / "examples" / "opengl_windy_text",
    saveWindowState: false,
  )
  frame.windowInfo = WindowInfo(
    box: initBox(0, 0, 900, 600),
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
    atlasSize = 1024,
    pixelScale = app.pixelScale,
  )

  proc redraw() =
    let winInfo = window.getWindowInfo()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h), uiFont)
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
