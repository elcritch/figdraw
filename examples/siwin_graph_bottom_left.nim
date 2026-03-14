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
const FontName {.strdefine: "figdraw.defaultfont".}: string = "Ubuntu.ttf"

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

proc makeRenderTree(windowW, windowH: float32, uiFont: FigFont): Renders =
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

  let sceneIdx = result.addChild(
    z,
    rootIdx,
    Fig(
      kind: nkTransform,
      childCount: 0,
      zlevel: z,
      transform: TransformStyle(
        translation: vec2(0.0'f32, windowH),
        matrix: scale(vec3(1.0'f32, -1.0'f32, 1.0'f32)),
        useMatrix: true,
      ),
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
    sceneIdx,
    plotRect,
    rgba(255, 255, 255, 255),
    corners = [10.0'f32, 10.0, 10.0, 10.0],
  )

  let gridLines = 10
  for i in 0 .. gridLines:
    let t = i.float32 / gridLines.float32
    let
      gx = plotRect.x + t * plotRect.w
      gy = plotRect.y + t * plotRect.h

    result.addRectNode(
      z,
      sceneIdx,
      rect(gx, plotRect.y, 1.0'f32, plotRect.h),
      rgba(225, 229, 238, 255),
    )
    result.addRectNode(
      z,
      sceneIdx,
      rect(plotRect.x, gy, plotRect.w, 1.0'f32),
      rgba(225, 229, 238, 255),
    )

  result.addRectNode(
    z,
    sceneIdx,
    rect(plotRect.x, plotRect.y, plotRect.w, 2.0'f32),
    rgba(60, 65, 80, 255),
  )
  result.addRectNode(
    z,
    sceneIdx,
    rect(plotRect.x, plotRect.y, 2.0'f32, plotRect.h),
    rgba(60, 65, 80, 255),
  )

  let samples = max(120, plotRect.w.int)
  let cycles = 2.0'f32 * PI

  for i in 0 .. samples:
    let t = i.float32 / samples.float32
    let x = plotRect.x + t * plotRect.w
    let yNorm = clamp(0.5'f32 + 0.35'f32 * sin(t * cycles), 0.0'f32, 1.0'f32)
    let y = plotRect.y + yNorm * plotRect.h
    result.addRectNode(
      z,
      sceneIdx,
      rect(x - 1.5'f32, y - 1.5'f32, 3.0'f32, 3.0'f32),
      rgba(230, 63, 63, 255),
    )

  # Origin marker at (0, 0) in plot-local graph space.
  result.addRectNode(
    z,
    sceneIdx,
    rect(plotRect.x - 3.0'f32, plotRect.y - 3.0'f32, 6.0'f32, 6.0'f32),
    rgba(39, 169, 110, 255),
  )

  let legendPadding = 12.0'f32
  let legendRect = rect(
    plotRect.x + plotRect.w - 300.0'f32,
    plotRect.y + plotRect.h - 20.0'f32 - 124.0'f32,
    280.0'f32,
    124.0'f32,
  )

  discard result.addChild(
    z,
    sceneIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: legendRect,
      fill: rgba(255, 255, 255, 230),
      stroke: RenderStroke(weight: 1.2'f32, fill: rgba(120, 130, 150, 180).color),
      corners: [8.0'f32, 8.0'f32, 8.0'f32, 8.0'f32],
    ),
  )

  let legendText =
    "Legend\n" &
    "Red points: y = 0.5 + 0.35*sin(2πx)\n" &
    "Green point: origin (0, 0)\n" &
    "Axes: bottom-left coordinates"
  let legendSelectionRange = 0'i16 .. 5'i16
  let legendTextRect = rect(
    legendRect.x + legendPadding,
    legendRect.y + legendPadding,
    legendRect.w - legendPadding * 2.0'f32,
    legendRect.h - legendPadding * 2.0'f32,
  )
  let legendLayout = typeset(
    rect(0, 0, legendTextRect.w, legendTextRect.h),
    [span(uiFont, rgba(35, 40, 52, 255), legendText)],
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
  )

  discard result.addChild(
    z,
    sceneIdx,
    Fig(
      kind: nkText,
      childCount: 0,
      zlevel: z,
      flags: {NfInvertY, NfSelectText},
      screenBox: legendTextRect,
      fill: rgba(255, 221, 122, 220),
      selectionRange: legendSelectionRange,
      textLayout: legendLayout,
    ),
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

  registerStaticTypeface("Ubuntu.ttf", "../data/Ubuntu.ttf")
  let typefaceId = loadTypeface(FontName, @["Ubuntu.ttf"])
  let uiFont = FigFont(typefaceId: typefaceId, size: 16.0'f32)

  var
    frames = 0
    fpsFrames = 0
    fpsStart = epochTime()

  proc redraw() =
    renderer.beginFrame()
    let logicalSize = appWindow.logicalSize()
    var renders = makeRenderTree(logicalSize.x, logicalSize.y, uiFont)
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
