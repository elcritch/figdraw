when defined(emscripten):
  import std/[times, strutils]
else:
  import std/[os, times, strutils]

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import chroma
  import figdraw
  import figdraw/windowing/siwinshim

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc makeRenderTree*(w, h: float32, image: ImageRef): Renders =
  result = newRenders()

  let rootIdx = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(30, 30, 30, 255),
    ),
  )

  result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(40, 40, 320, 320),
      fill: rgba(80, 80, 80, 255),
      corners: [16'u16, 16'u16, 16'u16, 16'u16],
    ),
  )

  result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkImage,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(60, 60, 280, 280),
      image: imageStyle(image),
    ),
  )

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  let image = loadImageRef("img1.png")

  var app_running = true

  let title = siwinWindowTitle("Siwin Image RenderList")
  let size = ivec2(800, 600)
  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  when UseVulkanBackend:
    let renderer =
      newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = size, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
    let renderer =
      newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()

  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin Image RenderList")

  proc redraw() =
    renderer.beginFrame()
    let sz = appWindow.logicalSize()
    var renders = makeRenderTree(sz.x, sz.y, image)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      app_running = false,
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
    while app_running and appWindow.opened:
      appWindow.redraw()
      appWindow.step()

      inc frames
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        echo "fps: ", fps
        fpsFrames = 0
        fpsStart = now
      if RunOnce and frames >= 1:
        app_running = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      appWindow.close()
