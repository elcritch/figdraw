import std/[os, times, monotimes, strformat]

import sdl2 except rect

import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/utils/glutils

import renderlist_100_common

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
const NoSleep {.booldefine: "figdraw.noSleep".}: bool = true
var globalFrame = 0

type SdlWindow = ref object
  window: WindowPtr
  glContext: GlContextPtr
  focused: bool
  minimized: bool

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
  setFigDataDir(getCurrentDir() / "data")

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  let typefaceId = getTypefaceImpl("Ubuntu.ttf")
  let fpsFont = UiFont(typefaceId: typefaceId, size: 18.0'f32,
      lineHeightScale: 1.0)
  var fpsText = "0.0 FPS"

  var frame = AppFrame(
    windowTitle: "figdraw: SDL2 RenderList (100)",
  )
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, 800, 600),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  let window = newSdlWindow(frame.addr)

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = (when not defined(useFigDrawTextures): 192 else: 2048),
    pixelScale = app.pixelScale,
  )

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0
  var lastElementCount = 0

  proc redraw() =
    let winInfo = window.getWindowInfo()

    let t0 = getMonoTime()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h),
      globalFrame)
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)
    lastElementCount = renders.layers[0.ZLevel].nodes.len

    let hudMargin = 12.0'f32
    let hudW = 180.0'f32
    let hudH = 34.0'f32
    let hudRect = rect(
      winInfo.box.w.float32 - hudW - hudMargin,
      hudMargin,
      hudW,
      hudH,
    )

    discard renders.layers[0.ZLevel].addRoot(Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: hudRect,
      fill: rgba(0, 0, 0, 155).color,
      corners: [8.0'f32, 8.0, 8.0, 8.0],
    ))

    let hudTextPadX = 10.0'f32
    let hudTextPadY = 6.0'f32
    let hudTextRect = rect(
      hudRect.x + hudTextPadX,
      hudRect.y + hudTextPadY,
      hudRect.w - hudTextPadX * 2,
      hudRect.h - hudTextPadY * 2,
    )

    let fpsLayout = typeset(
      rect(0, 0, hudTextRect.w, hudTextRect.h),
      [(fpsFont, fpsText)],
      hAlign = Right,
      vAlign = Middle,
      minContent = false,
      wrap = false,
    )

    discard renders.layers[0.ZLevel].addRoot(Fig(
      kind: nkText,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: hudTextRect,
      fill: rgba(255, 255, 255, 245).color,
      textLayout: fpsLayout,
    ))

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
        fpsText = fmt"{fps:0.1f} FPS"
        let avgMake = makeRenderTreeMsSum / max(1, fpsFrames).float
        let avgRender = renderFrameMsSum / max(1, fpsFrames).float
        echo "fps: ", fps, " | elems: ", lastElementCount,
          " | makeRenderTree avg(ms): ", avgMake, " | renderFrame avg(ms): ",
          avgRender
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0

      when RunOnce:
        if frames >= 1:
          app.running = false

      when not NoSleep:
        if app.running:
          sleep(16)
  finally:
    window.closeWindow()
