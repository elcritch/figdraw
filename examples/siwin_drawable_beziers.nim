import std/math
when not defined(emscripten):
  import std/os

import chronicles

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw
  import figdraw/windowing/siwinshim

logScope:
  scope = "siwin_drawable_beziers"

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

func localPoint(area: Rect, x, y: float32): Vec2 =
  vec2(area.w * x, area.h * y)

proc drawableNode(
    area: Rect,
    fill: Fill,
    stroke: RenderStroke,
    ops: seq[DrawableOp],
    drawSteps: uint16 = 0'u16,
    drawAa: float32 = 0.0'f32,
): Fig =
  Fig(
    kind: nkDrawable,
    screenBox: area,
    fill: fill,
    drawStroke: stroke,
    drawSteps: drawSteps,
    drawAa: drawAa,
    drawOps: ops,
  )

proc addDrawableNode(
    renders: var Renders,
    z: ZLevel,
    parentIdx: FigIdx,
    area: Rect,
    fill: Fill,
    stroke: RenderStroke,
    ops: seq[DrawableOp],
    drawSteps: uint16 = 0'u16,
    drawAa: float32 = 0.0'f32,
) =
  if ops.len == 0:
    return
  discard renders.addChild(
    z, parentIdx, drawableNode(area, fill, stroke, ops, drawSteps, drawAa)
  )

proc controlLineOps(controls: openArray[Vec2]): seq[DrawableOp] =
  if controls.len < 2:
    return

  for i in 0 ..< controls.len - 1:
    result.add drawableLine(controls[i], controls[i + 1])

proc controlPointOps(controls: openArray[Vec2], radius: float32): seq[DrawableOp] =
  for point in controls:
    result.add drawableCircle(point, radius)

proc addDrawableDemo(renders: var Renders, z: ZLevel, parentIdx: FigIdx, area: Rect) =
  let
    transparent = fill(rgba(0, 0, 0, 0))
    blue = rgba(26, 99, 214, 255)
    rose = rgba(221, 62, 125, 255)
    green = rgba(40, 153, 94, 255)
    mutedBlue = rgba(26, 99, 214, 70)
    mutedRose = rgba(221, 62, 125, 70)
    mutedGreen = rgba(40, 153, 94, 70)
    mutedInk = rgba(82, 92, 112, 120)

  let
    arcCenter = localPoint(area, 0.76'f32, 0.75'f32)
    quadratic = [
      localPoint(area, 0.08'f32, 0.72'f32),
      localPoint(area, 0.29'f32, 0.10'f32),
      localPoint(area, 0.52'f32, 0.64'f32),
    ]
    cubic = [
      localPoint(area, 0.14'f32, 0.38'f32),
      localPoint(area, 0.36'f32, 0.04'f32),
      localPoint(area, 0.58'f32, 0.94'f32),
      localPoint(area, 0.83'f32, 0.42'f32),
    ]
    generic = [
      localPoint(area, 0.10'f32, 0.58'f32),
      localPoint(area, 0.25'f32, 0.88'f32),
      localPoint(area, 0.43'f32, 0.44'f32),
      localPoint(area, 0.64'f32, 0.80'f32),
      localPoint(area, 0.91'f32, 0.20'f32),
    ]

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 3.0'f32, fill: mutedInk, cap: scSquare, join: sjBevel),
    @[
      drawableArc(
        arcCenter,
        min(area.w, area.h) * 0.10'f32,
        -PI.float32 * 1.10'f32,
        PI.float32 * 1.35'f32,
      ),
      drawableArc(
        arcCenter,
        min(area.w, area.h) * 0.15'f32,
        -PI.float32 * 0.85'f32,
        PI.float32 * 0.95'f32,
      ),
    ],
    drawSteps = 24'u16,
    drawAa = 0.85'f32,
  )

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 2.0'f32, fill: rgba(80, 90, 110, 90)),
    @[
      drawableRect(
        rect(18.0'f32, 18.0'f32, area.w - 36.0'f32, area.h - 36.0'f32),
        corners = [16'u16, 16'u16, 16'u16, 16'u16],
      )
    ],
  )

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 1.4'f32, fill: mutedBlue),
    controlLineOps(quadratic),
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    mutedBlue,
    RenderStroke(weight: 1.5'f32, fill: rgba(255, 255, 255, 230)),
    controlPointOps(quadratic, 5.0'f32),
  )

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 1.4'f32, fill: mutedRose),
    controlLineOps(cubic),
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    mutedRose,
    RenderStroke(weight: 1.5'f32, fill: rgba(255, 255, 255, 230)),
    controlPointOps(cubic, 5.0'f32),
  )

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 1.4'f32, fill: mutedGreen),
    controlLineOps(generic),
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    mutedGreen,
    RenderStroke(weight: 1.5'f32, fill: rgba(255, 255, 255, 230)),
    controlPointOps(generic, 5.0'f32),
  )

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 7.0'f32, fill: blue, cap: scButt),
    @[drawableBezier(quadratic)],
    drawAa = 0.9'f32,
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 8.0'f32, fill: rose, cap: scSquare, join: sjBevel),
    @[drawableBezier(cubic)],
    drawSteps = 24'u16,
    drawAa = 0.9'f32,
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    transparent,
    RenderStroke(weight: 5.5'f32, fill: green, cap: scRound, join: sjRound),
    @[drawableBezier(generic)],
    drawSteps = 32'u16,
    drawAa = 0.9'f32,
  )

  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    blue,
    RenderStroke(weight: 2.0'f32, fill: rgba(255, 255, 255, 230)),
    @[drawableCircle(localPoint(area, 0.52'f32, 0.64'f32), 9.0'f32)],
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    rose,
    RenderStroke(weight: 2.0'f32, fill: rgba(255, 255, 255, 230)),
    @[drawableCircle(localPoint(area, 0.83'f32, 0.42'f32), 9.0'f32)],
  )
  renders.addDrawableNode(
    z,
    parentIdx,
    area,
    green,
    RenderStroke(weight: 2.0'f32, fill: rgba(255, 255, 255, 230)),
    @[drawableCircle(localPoint(area, 0.91'f32, 0.20'f32), 8.0'f32)],
  )

proc makeRenderTree*(w, h: float32): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  let z = 0.ZLevel
  let rootIdx = result.addRoot(
    z,
    Fig(kind: nkRectangle, screenBox: rect(0, 0, w, h), fill: rgba(246, 248, 252, 255)),
  )

  let
    margin = max(28.0'f32, min(w, h) * 0.08'f32)
    panel = rect(
      margin,
      margin,
      max(320.0'f32, w - margin * 2.0'f32),
      max(260.0'f32, h - margin * 2.0'f32),
    )

  discard result.addChild(
    z,
    rootIdx,
    Fig(
      kind: nkRectangle,
      screenBox: panel,
      fill: rgba(255, 255, 255, 255),
      corners: [18.0'f32, 18.0'f32, 18.0'f32, 18.0'f32],
      stroke: RenderStroke(weight: 1.0'f32, fill: rgba(198, 206, 220, 255)),
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 18.0'f32,
          spread: 4.0'f32,
          x: 0.0'f32,
          y: 10.0'f32,
          fill: rgba(25, 35, 55, 42),
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

  result.addDrawableDemo(z, rootIdx, panel)

when isMainModule:
  var appRunning = true

  let title = siwinWindowTitle("Siwin Drawable Beziers + Arcs")
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
    siwinWindowTitle(renderer, appWindow, "Siwin Drawable Beziers + Arcs")

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
