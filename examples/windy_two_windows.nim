import std/os
import std/strutils
import chroma

when defined(useWindex):
  import windex
else:
  import figdraw/windowing/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

type WindowPalette = object
  bg: Color
  card: Color
  accent: Color

type DemoWindow = ref object
  window: Window
  renderer: FigRenderer[WindyRenderBackend]
  renders: Renders
  lastSize: Vec2
  palette: WindowPalette
  isOpen: bool
  useAutoScale: bool
  fixedScale: float

proc makeRenderTree(w, h: float32, palette: WindowPalette): Renders =
  result = Renders()

  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(0, 0, w, h),
      fill: palette.bg,
    ),
  )

  let panelW = min(420.0'f32, max(220.0'f32, w * 0.55'f32))
  let panelH = min(280.0'f32, max(170.0'f32, h * 0.5'f32))
  let panelX = (w - panelW) * 0.5'f32
  let panelY = (h - panelH) * 0.5'f32

  let barW = panelW * 0.75'f32
  let barX = panelX + (panelW - barW) * 0.5'f32
  let barH = 26.0'f32

  discard result.addChild(
    0.ZLevel,
    root,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(panelX, panelY, panelW, panelH),
      corners: [22.0'f32, 22.0, 22.0, 22.0],
      fill: palette.card,
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 14,
          spread: 3,
          x: 0,
          y: 12,
          color: rgba(0, 0, 0, 55).color,
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )

  for i in 0 .. 2:
    discard result.addChild(
      0.ZLevel,
      root,
      Fig(
        kind: nkRectangle,
        childCount: 0,
        screenBox: rect(barX, panelY + 38.0'f32 + i.float32 * 44.0'f32, barW, barH),
        corners: [10.0'f32, 10.0, 10.0, 10.0],
        fill:
          if i == 1:
            palette.accent
          else:
            rgba(255, 255, 255, 185).color,
      ),
    )

proc refreshScale(state: DemoWindow) =
  if state.useAutoScale:
    setFigUiScale state.window.contentScale()
  else:
    setFigUiScale state.fixedScale

proc redraw(state: DemoWindow) =
  if not state.isOpen:
    return
  state.refreshScale()
  state.renderer.beginFrame()
  let sz = state.window.logicalSize()
  if sz != state.lastSize:
    state.lastSize = sz
    state.renders = makeRenderTree(sz.x, sz.y, state.palette)
  state.renderer.renderFrame(state.renders, sz)
  state.renderer.endFrame()

proc newDemoWindow(
    size: IVec2,
    title: string,
    palette: WindowPalette,
    useAutoScale: bool,
    fixedScale: float,
): DemoWindow =
  let window = newWindyWindow(size = size, fullscreen = false, title = title)
  let renderer =
    glrenderer.newFigRenderer(atlasSize = 192, backendState = WindyRenderBackend())
  renderer.setupBackend(window)
  result = DemoWindow(
    window: window,
    renderer: renderer,
    renders: Renders(),
    lastSize: vec2(0.0'f32, 0.0'f32),
    palette: palette,
    isOpen: true,
    useAutoScale: useAutoScale,
    fixedScale: fixedScale,
  )
  result.refreshScale()
  if size != size.scaled():
    window.size = size.scaled()

proc installHandlers(state: DemoWindow) =
  state.window.onCloseRequest = proc() =
    if state.isOpen:
      state.isOpen = false
      state.window.close()
  state.window.onResize = proc() =
    if state.isOpen:
      state.refreshScale()
      state.redraw()

when isMainModule:
  let hdiEnv = getEnv("HDI")
  let useAutoScale = hdiEnv.len == 0
  let fixedScale =
    if useAutoScale:
      1.0
    else:
      hdiEnv.parseFloat()

  let left = newDemoWindow(
    size = ivec2(700, 500),
    title = windyWindowTitle("Two Windows: Left"),
    palette = WindowPalette(
      bg: rgba(242, 246, 255, 255).color,
      card: rgba(214, 227, 252, 255).color,
      accent: rgba(60, 112, 240, 255).color,
    ),
    useAutoScale = useAutoScale,
    fixedScale = fixedScale,
  )
  let right = newDemoWindow(
    size = ivec2(700, 500),
    title = windyWindowTitle("Two Windows: Right"),
    palette = WindowPalette(
      bg: rgba(255, 245, 238, 255).color,
      card: rgba(255, 224, 201, 255).color,
      accent: rgba(233, 113, 35, 255).color,
    ),
    useAutoScale = useAutoScale,
    fixedScale = fixedScale,
  )

  left.installHandlers()
  right.installHandlers()

  var appRunning = true
  var frames = 0

  try:
    while appRunning and (left.isOpen or right.isOpen):
      pollEvents()
      left.redraw()
      right.redraw()

      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        appRunning = left.isOpen or right.isOpen
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      if left.isOpen:
        left.isOpen = false
        left.window.close()
      if right.isOpen:
        right.isOpen = false
        right.window.close()
