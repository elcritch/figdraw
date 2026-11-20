import std/os
import figdraw
import figdraw/windowing

const RunOnce {.booldefine: "figdraw.runOnce".} = false

proc makeScene(size, pointer: Vec2): Renders =
  let
    level = 0.ZLevel
    panel = rect(size.x * 0.2, size.y * 0.25, size.x * 0.6, size.y * 0.5)
    corners = [20'u16, 20, 20, 20]
    cutterSize = 56'f32
  result = newRenders()

  # The stripe and card fill sit behind the border and show through the cutout.
  discard result.addRoot(
    level,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, panel.y - 14, size.x, 28),
      fill: rgba(222, 231, 244, 255),
    ),
  )
  discard result.addRoot(
    level,
    Fig(
      kind: nkRectangle,
      screenBox: panel,
      corners: corners,
      fill: rgba(242, 247, 255, 255),
    ),
  )
  let cutter = result.addRoot(
    level,
    Fig(
      kind: nkFrame,
      screenBox: rect(
        pointer.x - cutterSize / 2, pointer.y - cutterSize / 2, cutterSize, cutterSize
      ),
      corners: [28'u16, 28, 28, 28],
      flags: {NfInverseRectMaskContent},
    ),
  )
  discard result.addChild(
    level, cutter, figRoundedRectBorder(panel, corners, rgba(30, 66, 143, 255), 10)
  )

when isMainModule:
  let title = "Inverse mask | Move the pointer across the border"
  let size = ivec2(640, 400)
  when UseOpenGlBackend:
    let window = newSiwinWindow(size = size, title = title)
    window.firstStep()
    window.makeCurrent()
    let renderer = newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
  else:
    let renderer = newFigRenderer(atlasSize = 64, backendState = SiwinRenderBackend())
    let window = newSiwinWindow(renderer, size = size, title = title)
  let autoScale = window.configureUiScale()
  when defined(linux) or defined(bsd):
    if window.siwinDisplayServerName() == "x11" and size != size.scaled():
      window.size = size.scaled()
  renderer.setupBackend(window)
  window.title = siwinWindowTitle(renderer, window, title)
  var
    pointer: Vec2
    hasPointer = false
    rendered = false
    running = true

  proc redraw() =
    let size = window.logicalSize()
    if size.x > 0 and size.y > 0:
      let center =
        if hasPointer:
          pointer
        else:
          size * vec2(0.5, 0.25)
      var scene = makeScene(size, center)
      renderer.beginFrame()
      renderer.renderFrame(scene, size, clearColor = color(0.96, 0.97, 0.99, 1))
      renderer.endFrame()
      rendered = true

  window.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      running = false,
    onResize: proc(e: ResizeEvent) =
      window.refreshUiScale(autoScale)
      window.redraw(),
    onMouseMove: proc(e: MouseMoveEvent) =
      pointer = window.mouse.pos
      if window.inputUsesBackingPixels():
        pointer = pointer.descaled()
      hasPointer = true
      window.redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        running = false
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  when not UseOpenGlBackend:
    window.firstStep()
  window.refreshUiScale(autoScale)
  window.redraw()
  try:
    while running and window.opened:
      window.step()
      if RunOnce and rendered:
        break
      sleep(8)
  finally:
    renderer.finishPendingFrames()
    window.close()
