when defined(emscripten):
  import std/[times, math]
else:
  import std/[os, times, math]

import chroma

import figdraw/windowing/siwinshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc addRectNode(
    renders: var Renders,
    z: ZLevel,
    parentIdx: FigIdx,
    box: Rect,
    color: ColorRGBA,
    corners: array[DirectionCorners, float32] = [0.0'f32, 0.0, 0.0, 0.0],
) =
  discard renders.addChild(
    z,
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: box,
      fill: color,
      corners: corners,
    ),
  )

proc makeRenderTree(windowW, windowH: float32): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  let z = 0.ZLevel

  let rootIdx = result.addRoot(
    z,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rect(0, 0, windowW, windowH),
      fill: rgba(248, 249, 253, 255),
    ),
  )

  let margin = max(36.0'f32, min(windowW, windowH) * 0.08'f32)
  let plotRect = rect(
    margin,
    margin,
    max(40.0'f32, windowW - margin * 2),
    max(40.0'f32, windowH - margin * 2),
  )

  result.addRectNode(
    z,
    rootIdx,
    plotRect,
    rgba(255, 255, 255, 255),
    corners = [10.0'f32, 10.0, 10.0, 10.0],
  )

  let graphIdx = result.addChild(
    z,
    rootIdx,
    Fig(
      kind: nkTransform,
      childCount: 0,
      zlevel: z,
      transform: TransformStyle(
        # Convert the graph to bottom-left origin coordinates.
        translation: vec2(plotRect.x, plotRect.y + plotRect.h),
        matrix: scale(vec3(1.0'f32, -1.0'f32, 1.0'f32)),
        useMatrix: true,
      ),
    ),
  )

  let gridLines = 10
  for i in 0 .. gridLines:
    let t = i.float32 / gridLines.float32
    let gx = t * plotRect.w
    let gy = t * plotRect.h

    result.addRectNode(
      z, graphIdx, rect(gx, 0, 1.0'f32, plotRect.h), rgba(225, 229, 238, 255)
    )
    result.addRectNode(
      z, graphIdx, rect(0, gy, plotRect.w, 1.0'f32), rgba(225, 229, 238, 255)
    )

  result.addRectNode(
    z, graphIdx, rect(0, 0, plotRect.w, 2.0'f32), rgba(60, 65, 80, 255)
  )
  result.addRectNode(
    z, graphIdx, rect(0, 0, 2.0'f32, plotRect.h), rgba(60, 65, 80, 255)
  )

  let samples = max(120, plotRect.w.int)
  let cycles = 2.0'f32 * PI

  for i in 0 .. samples:
    let t = i.float32 / samples.float32
    let x = t * plotRect.w
    let yNorm = clamp(0.5'f32 + 0.35'f32 * sin(t * cycles), 0.0'f32, 1.0'f32)
    let y = yNorm * plotRect.h
    result.addRectNode(
      z,
      graphIdx,
      rect(x - 1.5'f32, y - 1.5'f32, 3.0'f32, 3.0'f32),
      rgba(230, 63, 63, 255),
    )

  # Origin marker at (0, 0) in graph space.
  result.addRectNode(
    z, graphIdx, rect(-3.0'f32, -3.0'f32, 6.0'f32, 6.0'f32), rgba(39, 169, 110, 255)
  )

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var appRunning = true

  let title = siwinWindowTitle("Siwin Bottom-Left Graph")
  let size = ivec2(960, 640)
  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize = 1024, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = size, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
    let renderer = newFigRenderer(atlasSize = 1024, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()

  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin Bottom-Left Graph")

  var
    frames = 0
    fpsFrames = 0
    fpsStart = epochTime()

  proc redraw() =
    renderer.beginFrame()
    let logicalSize = appWindow.logicalSize()
    var renders = makeRenderTree(logicalSize.x, logicalSize.y)
    renderer.renderFrame(renders, logicalSize)
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
        echo "fps: ", fpsFrames.float / elapsed
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
