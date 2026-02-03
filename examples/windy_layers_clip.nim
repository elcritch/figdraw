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
  var baseList = RenderList()
  discard baseList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-5).ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(230, 230, 230, 255).color,
    )
  )
  discard baseList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: (-5).ZLevel,
      screenBox: rect(0, 0, 360, h),
      fill: rgba(220, 40, 40, 255).color,
    )
  )

  var midList = RenderList()
  discard midList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(80, 40, 240, 160),
      fill: rgba(40, 180, 90, 255).color,
    )
  )

  let leftIdx = midList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(380, 40, 140, 200),
      fill: rgba(200, 200, 200, 255).color,
    )
  )
  discard midList.addChild(
    leftIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(360, 110, 200, 60),
      fill: rgba(220, 60, 60, 255).color,
    ),
  )

  let rightIdx = midList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(540, 40, 140, 200),
      fill: rgba(200, 200, 200, 255).color,
      flags: {NfClipContent},
    )
  )
  discard midList.addChild(
    rightIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(520, 110, 200, 60),
      fill: rgba(60, 120, 220, 255).color,
    ),
  )

  var topList = RenderList()
  discard topList.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 10.ZLevel,
      screenBox: rect(160, 80, 120, 80),
      fill: rgba(60, 90, 220, 255).color,
    )
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[(-5).ZLevel] = baseList
  result.layers[0.ZLevel] = midList
  result.layers[10.ZLevel] = topList
  result.layers.sort(
    proc(x, y: auto): int =
      cmp(x[0], y[0])
  )

when isMainModule:
  var appRunning = true

  let title = "figdraw: Windy Layers + Clip"
  let size = ivec2(720, 320)
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
