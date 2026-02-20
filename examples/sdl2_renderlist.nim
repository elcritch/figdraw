import std/[os, times]

import chroma
import sdl2 except rect

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as glrenderer
import figdraw/utils/glutils

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

when UseMetalBackend or UseVulkanBackend:
  {.
    error:
      "sdl2 examples only support OpenGL; use windy examples for Metal/Vulkan (or pass -d:figdraw.vulkan=off)."
  .}

type SdlWindow = ref object
  window: WindowPtr
  glContext: GlContextPtr
  focused: bool
  minimized: bool

var app_running = true

proc makeRenderTree*(w, h: float32): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  let rootIdx = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 255),
    ),
  )

  discard result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      corners: [10.0'f32, 20.0, 30.0, 40.0],
      screenBox: rect(60, 60, 220, 140),
      fill: rgba(220, 40, 40, 255),
      stroke: RenderStroke(weight: 5.0, fill: rgba(0, 0, 0, 255).color),
    ),
  )
  discard result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(320, 120, 220, 140),
      fill: rgba(40, 180, 90, 255),
      shadows: [
        RenderShadow(
          style: DropShadow, blur: 10, spread: 10, x: 10, y: 10, fill: blackColor
        ),
        RenderShadow(),
        RenderShadow(),
        RenderShadow(),
      ],
    ),
  )
  discard result.addChild(
    0.ZLevel,
    rootIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      screenBox: rect(180, 300, 220, 140),
      fill: rgba(60, 90, 220, 255),
    ),
  )

proc newSdlWindow(size: IVec2, title: string): SdlWindow =
  if sdl2.init(INIT_VIDEO) != SdlSuccess:
    quit "SDL2 init failed: " & $sdl2.getError()

  discard glSetAttribute(SDL_GL_CONTEXT_MAJOR_VERSION, openglVersion[0].cint)
  discard glSetAttribute(SDL_GL_CONTEXT_MINOR_VERSION, openglVersion[1].cint)
  discard glSetAttribute(SDL_GL_CONTEXT_PROFILE_MASK, SDL_GL_CONTEXT_PROFILE_CORE)
  discard glSetAttribute(SDL_GL_DOUBLEBUFFER, 1)

  let flags = SDL_WINDOW_OPENGL or SDL_WINDOW_RESIZABLE or SDL_WINDOW_ALLOW_HIGHDPI
  let window = createWindow(
    title.cstring, SDL_WINDOWPOS_CENTERED, SDL_WINDOWPOS_CENTERED, size.x.cint,
    size.y.cint, flags,
  )
  if window.isNil:
    quit "SDL2 window creation failed: " & $sdl2.getError()

  let glContext = glCreateContext(window)
  if glContext.isNil:
    quit "SDL2 GL context creation failed: " & $sdl2.getError()

  discard glMakeCurrent(window, glContext)
  startOpenGL(openglVersion)

  result =
    SdlWindow(window: window, glContext: glContext, focused: true, minimized: false)
  discard

proc swapBuffers*(w: SdlWindow) =
  w.window.glSwapWindow()

proc pollEvents*(w: SdlWindow, onResize: proc() {.closure.} = nil) =
  var evt = defaultEvent
  while pollEvent(evt):
    case evt.kind
    of QuitEvent:
      app_running = false
    of WindowEvent:
      let winEvent = evt.window()
      case winEvent.event
      of WindowEvent_Close:
        app_running = false
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

proc logicalSize*(w: SdlWindow): Vec2 =
  var winW, winH: cint
  var drawW, drawH: cint
  w.window.getSize(winW, winH)
  w.window.glGetDrawableSize(drawW, drawH)

  result.x = winW.float32.descaled()
  result.y = winH.float32.descaled()

proc setTitle*(w: SdlWindow, name: string) =
  w.window.setTitle(name.cstring)

proc closeWindow*(w: SdlWindow) =
  if not w.glContext.isNil:
    glDeleteContext(w.glContext)
  if not w.window.isNil:
    destroy(w.window)
  sdl2.quit()

when isMainModule:
  setFigUiScale 1.0

  let title = "figdraw: SDL2 RenderList"
  let size = ivec2(800, 600)

  let window = newSdlWindow(size, title)
  let renderer = glrenderer.newFigRenderer(atlasSize = 256)

  proc redraw() =
    let sz = window.logicalSize()
    var renders = makeRenderTree(sz.x, sz.y)
    renderer.renderFrame(renders, sz)
    window.swapBuffers()

  try:
    var frames = 0
    var fpsFrames = 0
    var fpsStart = epochTime()
    while app_running:
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
        app_running = false
      else:
        sleep(16)
  finally:
    window.closeWindow()
