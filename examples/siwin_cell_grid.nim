when defined(emscripten):
  import std/[times, strutils]
else:
  import std/[os, times, strutils]

import figdraw/windowing/siwinshim

import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
const GridColumns {.intdefine: "figdraw.cols".} = 24
const GridRows {.intdefine: "figdraw.rows".} = 32
const GridGap {.intdefine: "figdraw.gap".} = 6

proc cellColor(cellId: int): Color =
  let palette = [
    rgba(255, 205, 210, 255).color,
    rgba(255, 224, 178, 255).color,
    rgba(255, 245, 157, 255).color,
    rgba(200, 230, 201, 255).color,
    rgba(178, 235, 242, 255).color,
    rgba(209, 196, 233, 255).color,
  ]
  result = palette[cellId mod palette.len]

proc makeRenderTree(windowW, windowH: float32, labelFont: FigFont): Renders =
  result = Renders()
  let z = 0.ZLevel

  let rootIdx = result.addRoot(
    z,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rect(0, 0, windowW, windowH),
      fill: rgba(243, 246, 252, 255).color,
    ),
  )

  let
    gap = GridGap.float32
    margin = max(28.0'f32, min(windowW, windowH) * 0.04'f32)
    usableW = max(1.0'f32, windowW - margin * 2 - gap * (GridColumns - 1).float32)
    usableH = max(1.0'f32, windowH - margin * 2 - gap * (GridRows - 1).float32)
    cellW = usableW / GridColumns.float32
    cellH = usableH / GridRows.float32

  var cellId = 0
  for row in 0 ..< GridRows:
    for col in 0 ..< GridColumns:
      let
        cellX = margin + col.float32 * (cellW + gap)
        cellY = margin + row.float32 * (cellH + gap)
        cellRect = rect(cellX, cellY, cellW, cellH)

      let cellIdx = result.addChild(
        z,
        rootIdx,
        Fig(
          kind: nkRectangle,
          childCount: 0,
          zlevel: z,
          screenBox: cellRect,
          fill: cellColor(cellId),
          corners: [2.0'f32, 2.0, 2.0, 4.0],
          stroke: RenderStroke(weight: 1.5, color: rgba(15, 20, 30, 38).color),
          shadows: [
            RenderShadow(
              style: DropShadow,
              blur: 4,
              spread: 0,
              x: 3,
              y: 3,
              color: rgba(0, 0, 0, 45).color,
            ),
            RenderShadow(),
            RenderShadow(),
            RenderShadow(),
          ],
        ),
      )

      let
        textInset = 10.0'f32
        textRect = rect(
          cellRect.x + textInset,
          cellRect.y + textInset,
          max(1.0'f32, cellRect.w - textInset * 2),
          max(1.0'f32, cellRect.h - textInset * 2),
        )
        textLayout = typeset(
          rect(0, 0, textRect.w, textRect.h),
          [(fs(labelFont, rgba(17, 22, 35, 235).color), "cell $" & $cellId)],
          hAlign = Center,
          vAlign = Middle,
          minContent = false,
          wrap = false,
        )

      discard result.addChild(
        z,
        cellIdx,
        Fig(
          kind: nkText,
          childCount: 0,
          zlevel: z,
          screenBox: textRect,
          fill: clearColor,
          textLayout: textLayout,
        ),
      )

      inc cellId

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var appRunning = true
  let
    title = siwinWindowTitle("Siwin Cell Grid")
    baseSize = ivec2(1080, 720)
    typefaceId = loadTypeface("Ubuntu.ttf")
    labelFont = FigFont(typefaceId: typefaceId, size: 8.0'f32)
  let appWindow = newSiwinWindow(size = baseSize, fullscreen = false, title = title)
  let renderer = newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()

  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin Cell Grid")

  var
    frames = 0
    fpsFrames = 0
    fpsStart = epochTime()

  proc redraw() =
    renderer.beginFrame()
    let logicalSize = appWindow.logicalSize()
    var renders = makeRenderTree(logicalSize.x, logicalSize.y, labelFont)
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
  finally:
    when not defined(emscripten):
      appWindow.close()
