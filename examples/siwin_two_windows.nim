import std/os
import chroma

import figdraw/windowing/siwinshim

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
  renderer: FigRenderer[SiwinRenderBackend]
  renders: Renders
  lastSize: Vec2
  useAutoScale: bool
  palette: WindowPalette

proc makeRenderTree(w, h: float32, palette: WindowPalette): Renders =
  result = Renders()

  let root = result.addRoot(
    0.ZLevel,
    Fig(kind: nkRectangle, childCount: 0, screenBox: rect(0, 0, w, h), fill: palette.bg),
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

proc redraw(state: DemoWindow) =
  state.renderer.beginFrame()
  let sz = state.window.logicalSize()
  if sz != state.lastSize:
    state.lastSize = sz
    state.renders = makeRenderTree(sz.x, sz.y, state.palette)
  state.renderer.renderFrame(state.renders, sz)
  state.renderer.endFrame()

proc newDemoWindow(size: IVec2, titleSuffix: string, palette: WindowPalette): DemoWindow =
  let window = newSiwinWindow(
    size = size,
    fullscreen = false,
    title = siwinWindowTitle(titleSuffix),
    vsync = true,
  )
  let renderer =
    glrenderer.newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
  let useAutoScale = window.configureUiScale()
  renderer.setupBackend(window)
  window.title = siwinWindowTitle(renderer, window, titleSuffix)
  result = DemoWindow(
    window: window,
    renderer: renderer,
    renders: Renders(),
    lastSize: vec2(0.0'f32, 0.0'f32),
    useAutoScale: useAutoScale,
    palette: palette,
  )

proc installHandlers(state: DemoWindow) =
  state.window.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      discard,
    onResize: proc(e: ResizeEvent) =
      state.window.refreshUiScale(state.useAutoScale)
      state.redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        close(e.window)
    ,
    onRender: proc(e: RenderEvent) =
      state.redraw(),
  )

when isMainModule:
  let left = newDemoWindow(
    size = ivec2(700, 500),
    titleSuffix = "Two Windows: Left",
    palette = WindowPalette(
      bg: rgba(242, 246, 255, 255).color,
      card: rgba(214, 227, 252, 255).color,
      accent: rgba(60, 112, 240, 255).color,
    ),
  )
  let right = newDemoWindow(
    size = ivec2(700, 500),
    titleSuffix = "Two Windows: Right",
    palette = WindowPalette(
      bg: rgba(255, 245, 238, 255).color,
      card: rgba(255, 224, 201, 255).color,
      accent: rgba(233, 113, 35, 255).color,
    ),
  )

  left.installHandlers()
  right.installHandlers()

  left.window.firstStep()
  right.window.firstStep()
  left.window.refreshUiScale(left.useAutoScale)
  right.window.refreshUiScale(right.useAutoScale)

  var appRunning = true
  var frames = 0

  try:
    while appRunning and (left.window.opened or right.window.opened):
      if left.window.opened:
        left.window.redraw()
      if right.window.opened:
        right.window.redraw()

      if left.window.opened:
        left.window.step()
      if right.window.opened:
        right.window.step()

      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        appRunning = left.window.opened or right.window.opened
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      if left.window.opened:
        left.window.close()
      if right.window.opened:
        right.window.close()
