import std/[os, times]

import chroma
import sdl2 except rect

import figdraw/commons
import figdraw/fignodes
import figdraw/renderer as glrenderer
import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

type SdlWindow = ref object
  window: WindowPtr
  glContext: GlContextPtr
  focused: bool
  minimized: bool

proc makeRenderTree*(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 255).color,
  ))

  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    corners: [10.0'f32, 20.0, 30.0, 40.0],
    screenBox: rect(60, 60, 220, 140),
    fill: rgba(220, 40, 40, 255).color,
    stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 255).color)
  ))
  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(320, 120, 220, 140),
    fill: rgba(40, 180, 90, 255).color,
    shadows: [
      RenderShadow(
        style: DropShadow,
        blur: 10,
        spread: 10,
        x: 10,
        y: 10,
        color: blackColor,
    ),
    RenderShadow(),
    RenderShadow(),
    RenderShadow(),
  ],
  ))
  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(180, 300, 220, 140),
    fill: rgba(60, 90, 220, 255).color,
  ))

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

proc getScaleInfo*(w: SdlWindow): ScaleInfo =
  var winW, winH: cint
  var drawW, drawH: cint
  w.window.getSize(winW, winH)
  w.window.glGetDrawableSize(drawW, drawH)
  if winW > 0 and winH > 0:
    result.x = drawW.float32 / winW.float32
    result.y = drawH.float32 / winH.float32
  else:
    result.x = 1.0
    result.y = 1.0

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

proc setTitle*(w: SdlWindow, name: string) =
  w.window.setTitle(name.cstring)

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
    windowTitle: "figdraw: SDL2 RenderList",
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
    atlasSize = 256,
    pixelScale = app.pixelScale,
  )

  proc redraw() =
    let winInfo = window.getWindowInfo()
    var renders = makeRenderTree(float32(winInfo.box.w), float32(winInfo.box.h))
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    window.swapBuffers()

  try:
    var frames = 0
    var fpsFrames = 0
    var fpsStart = epochTime()
    while app.running:
      window.pollEvents(onResize = redraw)
      redraw()

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
        app.running = false
      else:
        sleep(16)
  finally:
    window.closeWindow()
