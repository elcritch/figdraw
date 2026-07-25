import std/[os, strutils]

import pkg/opengl
import pkg/chroma
import pkg/chronicles

const
  openglMajor {.intdefine.} = 3
  openglMinor {.intdefine.} = 3
  openglVersion* = (openglMajor, openglMinor)

proc runtimeSoftwareOpenGlRequested*(): bool =
  ## Returns whether FigDraw should request a CPU-backed OpenGL implementation.
  getEnv("FIGDRAW_SOFTWARE_GL").strip().toLowerAscii() in ["1", "true", "yes", "on"]

func softwareOpenGlPlatformSupported*(): bool =
  ## Linux/BSD use Mesa's GL loader. Windows requires a Mesa WGL distribution
  ## beside the executable; the environment setting alone cannot replace the
  ## system OpenGL library.
  when defined(linux) or defined(bsd) or defined(windows): true else: false

proc configureSoftwareOpenGl*(): bool {.discardable.} =
  ## Configures Mesa before a window creates its OpenGL context.
  ##
  ## This runs automatically when this module is initialized. Call it directly
  ## if FIGDRAW_SOFTWARE_GL is set later during application startup.
  if not runtimeSoftwareOpenGlRequested():
    return false

  when defined(linux) or defined(bsd):
    putEnv("LIBGL_ALWAYS_SOFTWARE", "true")
    if getEnv("GALLIUM_DRIVER").strip().len == 0:
      putEnv("GALLIUM_DRIVER", "llvmpipe")
    true
  elif defined(windows):
    if getEnv("GALLIUM_DRIVER").strip().len == 0:
      putEnv("GALLIUM_DRIVER", "llvmpipe")
    true
  else:
    false

func isSoftwareOpenGlRenderer*(renderer: string): bool =
  ## Recognizes common CPU-backed OpenGL renderer names.
  let normalized = renderer.toLowerAscii()
  for marker in [
    "llvmpipe", "softpipe", "swiftshader", "swrast", "software rasterizer",
    "microsoft basic render driver", "gdi generic",
  ]:
    if marker in normalized:
      return true
  false

proc openGlString(name: GLenum): string =
  let value = cast[cstring](glGetString(name))
  if not value.isNil:
    result = $value

proc openGlVendor*(): string =
  openGlString(GL_VENDOR)

proc openGlRenderer*(): string =
  openGlString(GL_RENDERER)

proc openGlVersionString*(): string =
  openGlString(GL_VERSION)

proc softwareOpenGlActive*(): bool =
  isSoftwareOpenGlRenderer(openGlRenderer())

proc logOpenGlDriver() =
  let
    vendor = openGlVendor()
    renderer = openGlRenderer()
    version = openGlVersionString()
    software = isSoftwareOpenGlRenderer(renderer)
  info "OpenGL context ready",
    vendor = vendor, renderer = renderer, version = version, software = software
  if runtimeSoftwareOpenGlRequested() and not software:
    warn "Software OpenGL requested, but the active renderer is not recognized as software",
      renderer = renderer, platformSupported = softwareOpenGlPlatformSupported()

discard configureSoftwareOpenGl()

proc openglDebug*() =
  when defined(glDebugMessageCallback):
    let flags = glGetInteger(GL_CONTEXT_FLAGS)
    if (flags and GL_CONTEXT_FLAG_DEBUG_BIT.GLint) != 0:
      # Set up error logging
      proc printGlDebug(
          source, typ: GLenum,
          id: GLuint,
          severity: GLenum,
          length: GLsizei,
          message: ptr GLchar,
          userParam: pointer,
      ) {.stdcall.} =
        echo &"source={toHex(source.uint32)} type={toHex(typ.uint32)} " &
          &"id={id} severity={toHex(severity.uint32)}: {$message}"
        if severity != GL_DEBUG_SEVERITY_NOTIFICATION:
          running = false

      glDebugMessageCallback(printGlDebug, nil)
      glEnable(GL_DEBUG_OUTPUT_SYNCHRONOUS)
      glEnable(GL_DEBUG_OUTPUT)

  when defined(printGLVersion):
    echo getVersionString()
    echo "GL_VERSION:", cast[cstring](glGetString(GL_VERSION))
    echo "GL_SHADING_LANGUAGE_VERSION:",
      cast[cstring](glGetString(GL_SHADING_LANGUAGE_VERSION))

proc setOpenGlHints*() =
  # these don't work in windy?
  when defined(setOpenGlHintsEnabled):
    if msaa != msaaDisabled:
      windowHint(SAMPLES, msaa.cint)
    windowHint(OPENGL_FORWARD_COMPAT, GL_TRUE.cint)
    windowHint(OPENGL_PROFILE, OPENGL_CORE_PROFILE)
    windowHint(CONTEXT_VERSION_MAJOR, openglVersion[0].cint)
    windowHint(CONTEXT_VERSION_MINOR, openglVersion[1].cint)

iterator glErrors*(): string =
  var error: GLenum
  while (error = glGetError(); error != GL_NO_ERROR):
    yield "gl error: " & $error.uint32

proc clearDepthBuffer*() =
  glClear(GL_DEPTH_BUFFER_BIT)

proc clearColorBuffer*(color: Color) =
  glClearColor(color.r, color.g, color.b, color.a)
  glClear(GL_COLOR_BUFFER_BIT)

proc useDepthBuffer*(on: bool) =
  if on:
    glDepthMask(GL_TRUE)
    glEnable(GL_DEPTH_TEST)
    glDepthFunc(GL_LEQUAL)
  else:
    glDepthMask(GL_FALSE)
    glDisable(GL_DEPTH_TEST)

proc startOpenGL*(openglVersion: (int, int)) =
  when not defined(emscripten):
    loadExtensions()

  logOpenGlDriver()
  openglDebug()

  glEnable(GL_BLEND)
  glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)
  glBlendFuncSeparate(
    GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA, GL_ONE, GL_ONE_MINUS_SRC_ALPHA
  )

  useDepthBuffer(false)
