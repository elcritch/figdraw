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

when not UseMetalBackend:
  import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc newWindyWindow(size: IVec2, fullscreen = false, title = "FigDraw"): Window =
  let size = scaled(when defined(emscripten): ivec2(0, 0) else: size)
  let window = newWindow(title, size, visible = false)

  when not UseMetalBackend:
    startOpenGL(openglVersion)

  when not defined(emscripten):
    if fullscreen:
      window.fullscreen = true
    else:
      window.size = size
    window.visible = true
  when not UseMetalBackend:
    window.makeContextCurrent()

  return window

proc makeRenderTree*(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 255).color,
    )
  )

  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      corners: [10.0'f32, 20.0, 30.0, 40.0],
      screenBox: rect(60, 60, 220, 140),
      fill: rgba(220, 40, 40, 255).color,
      stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 255).color),
    ),
  )
  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(320, 120, 220, 140),
      fill: rgba(40, 180, 90, 255).color,
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 10,
          spread: 10,
          x: 10,
          y: 10,
          color: rgba(0, 0, 0, 55).color,
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )
  list.addChild(
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(180, 300, 220, 140),
      fill: rgba(60, 90, 220, 255).color,
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  app.running = true
  if getEnv("HDI") != "":
    app.uiScale = getEnv("HDI").parseFloat()
  else:
    app.uiScale = 1.0
  app.pixelScale = 1.0

  let size = ivec2(800, 600)
  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  let window = newWindyWindow(size = size,
                              fullscreen = false,
                              title = "figdraw: OpenGL + Windy RenderList")

  let renderer = glrenderer.newFigRenderer(atlasSize = 192, pixelScale = app.pixelScale)

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
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        app.running = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      window.close()
