when not defined(emscripten):
  import std/os

import chronicles

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw
  import figdraw/utils/drawutils
  import figdraw/windowing/siwinshim

logScope:
  scope = "siwin_dashed_dotted_borders"

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

func uniformCorners(radius: uint16): array[DirectionCorners, uint16] =
  for corner in DirectionCorners:
    result[corner] = radius

func cornerRadii(
    topLeft, topRight, bottomLeft, bottomRight: uint16
): array[DirectionCorners, uint16] =
  result[dcTopLeft] = topLeft
  result[dcTopRight] = topRight
  result[dcBottomLeft] = bottomLeft
  result[dcBottomRight] = bottomRight

proc addBackground(renders: var Renders, z: ZLevel, rootIdx: FigIdx, box: Rect) =
  discard renders.addChild(
    z,
    rootIdx,
    Fig(
      kind: nkRectangle,
      screenBox: box,
      fill: rgba(255, 255, 255, 245),
      corners: uniformCorners(18'u16),
      stroke: RenderStroke(weight: 1.0'f32, fill: rgba(198, 206, 220, 255)),
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 18.0'f32,
          spread: 4.0'f32,
          x: 0.0'f32,
          y: 10.0'f32,
          fill: rgba(25, 35, 55, 38),
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

proc addFilledBox(
    renders: var Renders,
    z: ZLevel,
    rootIdx: FigIdx,
    box: Rect,
    fillColor: ColorRGBA,
    corners: array[DirectionCorners, uint16],
) =
  discard renders.addChild(
    z,
    rootIdx,
    Fig(kind: nkRectangle, screenBox: box, fill: fillColor, corners: corners),
  )

proc addBorderDemos(renders: var Renders, z: ZLevel, rootIdx: FigIdx, panel: Rect) =
  let
    gap = max(18.0'f32, min(panel.w, panel.h) * 0.045'f32)
    itemW = max(160.0'f32, (panel.w - gap * 3.0'f32) * 0.5'f32)
    itemH = max(105.0'f32, (panel.h - gap * 3.0'f32) * 0.5'f32)
    left = panel.x + gap
    right = panel.x + panel.w - gap - itemW
    top = panel.y + gap
    bottom = panel.y + panel.h - gap - itemH

    dashedBox = rect(left, top, itemW, itemH)
    dottedBox = rect(right, top, itemW, itemH)
    mixedDashBox = rect(left, bottom, itemW, itemH)
    mixedDotBox = rect(right, bottom, itemW, itemH)

    blueCorners = uniformCorners(24'u16)
    greenCorners = uniformCorners(34'u16)
    roseCorners = cornerRadii(8'u16, 34'u16, 26'u16, 12'u16)
    goldCorners = cornerRadii(32'u16, 10'u16, 10'u16, 32'u16)

  renders.addFilledBox(z, rootIdx, dashedBox, rgba(235, 243, 255, 255), blueCorners)
  renders.addFilledBox(z, rootIdx, dottedBox, rgba(235, 248, 241, 255), greenCorners)
  renders.addFilledBox(z, rootIdx, mixedDashBox, rgba(255, 239, 246, 255), roseCorners)
  renders.addFilledBox(z, rootIdx, mixedDotBox, rgba(255, 248, 228, 255), goldCorners)

  discard renders.addChild(
    z,
    rootIdx,
    figDashedRoundedRectBorder(
      dashedBox,
      blueCorners,
      rgba(32, 96, 210, 255),
      weight = 5.0'f32,
      dashLength = 18.0'f32,
      gapLength = 10.0'f32,
    ),
  )
  discard renders.addChild(
    z,
    rootIdx,
    figDottedRoundedRectBorder(
      dottedBox,
      greenCorners,
      rgba(35, 145, 82, 255),
      weight = 7.0'f32,
      gapLength = 8.0'f32,
    ),
  )
  discard renders.addChild(
    z,
    rootIdx,
    figDashedRoundedRectBorder(
      mixedDashBox,
      roseCorners,
      rgba(210, 57, 120, 255),
      weight = 6.0'f32,
      dashLength = 26.0'f32,
      gapLength = 12.0'f32,
      offset = 16.0'f32,
      cap = scRound,
    ),
  )
  discard renders.addChild(
    z,
    rootIdx,
    figDottedRoundedRectBorder(
      mixedDotBox,
      goldCorners,
      rgba(176, 116, 20, 255),
      weight = 9.0'f32,
      gapLength = 11.0'f32,
      offset = 7.0'f32,
    ),
  )

proc makeRenderTree*(w, h: float32): Renders =
  result = Renders()

  let z = 0.ZLevel
  let rootIdx = result.addRoot(
    z,
    Fig(kind: nkRectangle, screenBox: rect(0, 0, w, h), fill: rgba(246, 248, 252, 255)),
  )

  let
    margin = max(24.0'f32, min(w, h) * 0.07'f32)
    panel = rect(
      margin,
      margin,
      max(420.0'f32, w - margin * 2.0'f32),
      max(300.0'f32, h - margin * 2.0'f32),
    )

  result.addBackground(z, rootIdx, panel)
  result.addBorderDemos(z, rootIdx, panel)

when isMainModule:
  var appRunning = true

  let title = siwinWindowTitle("Siwin Dashed + Dotted Borders")
  let size = ivec2(900, 620)
  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize = 512, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = size, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
    let renderer = newFigRenderer(atlasSize = 512, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()
  renderer.setupBackend(appWindow)
  appWindow.title =
    siwinWindowTitle(renderer, appWindow, "Siwin Dashed + Dotted Borders")

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
    var frames = 0
    while appRunning and appWindow.opened:
      appWindow.redraw()
      appWindow.step()
      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      appWindow.close()
