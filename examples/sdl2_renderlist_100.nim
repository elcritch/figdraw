import std/[os, times, random, math, monotimes]

import chroma
import sdl2 except rect

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
var globalFrame = 0

type SdlWindow = ref object
  window: WindowPtr
  glContext: GlContextPtr
  focused: bool
  minimized: bool

proc makeRenderTree*(w, h: float32): Renders =
  var list = RenderList()
  const copies = 400
  let t = globalFrame.float32 * 0.02'f32

  let rootId = 1.FigID
  list.nodes.add Fig(
    kind: nkRectangle,
    uid: rootId,
    parent: -1.FigID,
    childCount: 0,
    zlevel: 0.ZLevel,
    name: "root".toFigName(),
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 155).color,
  )

  list.rootIds = @[0.FigIdx]

  let maxX = max(0.0'f32, w - 220)
  let maxY = max(0.0'f32, h - 140)
  var rng = initRand((w.int shl 16) xor h.int xor 12345)

  for i in 0 ..< copies:
    let baseId = 2 + i * 3
    let baseX = rand(rng, 0.0'f32 .. maxX)
    let baseY = rand(rng, 0.0'f32 .. maxY)
    let jitterX = sin((t + i.float32 * 0.15'f32).float64).float32 * 20
    let jitterY = cos((t * 0.9'f32 + i.float32 * 0.2'f32).float64).float32 * 20
    let offsetX = min(max(baseX + jitterX, 0.0'f32), maxX)
    let offsetY = min(max(baseY + jitterY, 0.0'f32), maxY)

    let redIdx = list.nodes.len()
    list.nodes.add Fig(
      kind: nkRectangle,
      uid: FigID(baseId),
      parent: -1.FigID,
      childCount: 0,
      zlevel: 0.ZLevel,
      corners: [10.0'f32, 20.0, 30.0, 40.0],
      name: ("box-red-" & $i).toFigName(),
      screenBox: rect(60 + offsetX, 60 + offsetY, 220, 140),
      fill: rgba(220, 40, 40, 155).color,
      stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 155).color)
    )
    list.rootIds.add(redIdx.FigIdx)

    let greenIdx = list.nodes.len()
    list.nodes.add Fig(
      kind: nkRectangle,
      uid: FigID(baseId + 1),
      parent: -1.FigID,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: ("box-green-" & $i).toFigName(),
      screenBox: rect(320 + offsetX, 120 + offsetY, 220, 140),
      fill: rgba(40, 180, 90, 155).color,
      shadows: [
        RenderShadow(
          style: DropShadow,
          blur: 10,
          spread: 10,
          x: 10,
          y: 10,
          color: rgba(0,0,0,155).color,
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ]
    )
    list.rootIds.add(greenIdx.FigIdx)

    let blueIdx = list.nodes.len()
    list.nodes.add Fig(
      kind: nkRectangle,
      uid: FigID(baseId + 2),
      parent: -1.FigID,
      childCount: 0,
      zlevel: 0.ZLevel,
      name: ("box-blue-" & $i).toFigName(),
      screenBox: rect(180 + offsetX, 300 + offsetY, 220, 140),
      fill: rgba(60, 90, 220, 155).color,
    )
    list.rootIds.add(blueIdx.FigIdx)

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc newSdlWindow(frame: ptr AppFrame): SdlWindow =
  doAssert not frame.isNil
  if sdl2.init(INIT_VIDEO) != SdlSuccess:
    quit "SDL2 init failed: " & $sdl2.getError()

  discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, openglVersion[0].cint)
  discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, openglVersion[1].cint)
  discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)
  discard glSetAttribute(SDL_GL_DOUBLEBUFFER, 1)

  let winBox = frame[].windowInfo.box
  let flags = SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE or SDL_WINDOW_ALLOW_HIGHDPI
  let window = createWindow(
    frame[].windowTitle.cstring,
    SDL_WINDOWPOS_CENTERED,
    SDL_WINDOWPOS_CENTERED,
    winBox.w.cint,
    winBox.h.cint,
    flags,
  )
  if window.isNil:
    quit "SDL2 window creation failed: " & $sdl2.getError()

  let glContext = glCreateContext(window)
  if glContext.isNil:
    quit "SDL2 GL context creation failed: " & $sdl2.getError()

  discard glMakeCurrent(window, glContext)
  startOpenGL(openglVersion)

  result = SdlWindow(
    window: window,
    glContext: glContext,
    focused: true,
    minimized: false,
  )
  discard

proc swapBuffers*(w: SdlWindow) =
  w.window.glSwapWindow()

proc pollEvents*(w: SdlWindow, onResize: proc() {.closure.} = nil) =
  var evt = defaultEvent
  while pollEvent(evt):
    case evt.kind
    of QuitEvent:
      app.running = false
    of WindowEvent:
      let winEvent = evt.window()
      case winEvent.event
      of WindowEvent_Close:
        app.running = false
      of WindowEvent_Minimized:
        w.minimized = true
      of WindowEvent_Restored, WindowEvent_Shown, WindowEvent_Exposed,
          WindowEvent_Resized, WindowEvent_SizeChanged:
        w.minimized = false
        if onResize != nil:
          onResize()
      of WindowEvent_FocusGained:
        w.focused = true
      of WindowEvent_FocusLost:
        w.focused = false
      else:
        discard
    else:
      discard

proc getWindowInfo*(w: SdlWindow): WindowInfo =
  app.requestedFrame.inc
  var winW, winH: cint
  var drawW, drawH: cint
  w.window.getSize(winW, winH)
  w.window.glGetDrawableSize(drawW, drawH)

  result.box.w = winW.float32.descaled()
  result.box.h = winH.float32.descaled()
  result.minimized = w.minimized
  result.focused = w.focused
  result.fullscreen = false
  if winW > 0:
    result.pixelRatio = drawW.float32 / winW.float32
  else:
    result.pixelRatio = 1.0

proc closeWindow*(w: SdlWindow) =
  if not w.glContext.isNil:
    glDeleteContext(w.glContext)
  if not w.window.isNil:
    destroy(w.window)
  sdl2.quit()

when isMainModule:
  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  var frame = AppFrame(
    windowTitle: "figdraw: SDL2 RenderList (100)",
    windowStyle: FrameStyle.DecoratedResizable,
    configFile: getCurrentDir() / "examples" / "sdl2_renderlist_100",
    saveWindowState: false,
  )
  frame.windowInfo = WindowInfo(
    box: initBox(0, 0, 800, 600),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  let window = newSdlWindow(frame.addr)

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = 192,
    pixelScale = app.pixelScale,
  )

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0

  proc redraw() =
    let winInfo = window.getWindowInfo()

    let t0 = getMonoTime()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h))
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)

    let t1 = getMonoTime()
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    renderFrameMsSum += float((getMonoTime() - t1).inMilliseconds)

    window.swapBuffers()

  try:
    var frames = 0
    var fpsFrames = 0
    var fpsStart = epochTime()
    while app.running:
      window.pollEvents(onResize = redraw)
      redraw()

      inc frames
      inc globalFrame
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        let avgMake = makeRenderTreeMsSum / max(1, fpsFrames).float
        let avgRender = renderFrameMsSum / max(1, fpsFrames).float
        echo "fps: ", fps, " | makeRenderTree avg(ms): ", avgMake,
          " | renderFrame avg(ms): ", avgRender
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0
      if RunOnce and frames >= 1:
        app.running = false
      else:
        sleep(16)
  finally:
    window.closeWindow()
