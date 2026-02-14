import std/[os, unittest]

import figdraw/figrender

proc withCleanEnv(body: proc()) =
  let hadForce = existsEnv("FIGDRAW_FORCE_OPENGL")
  let oldForce = getEnv("FIGDRAW_FORCE_OPENGL")
  let hadBackend = existsEnv("FIGDRAW_BACKEND")
  let oldBackend = getEnv("FIGDRAW_BACKEND")
  defer:
    if hadForce:
      putEnv("FIGDRAW_FORCE_OPENGL", oldForce)
    else:
      delEnv("FIGDRAW_FORCE_OPENGL")
    if hadBackend:
      putEnv("FIGDRAW_BACKEND", oldBackend)
    else:
      delEnv("FIGDRAW_BACKEND")
  body()

suite "figrender env overrides":
  test "force opengl wins over backend selection":
    withCleanEnv proc() =
      putEnv("FIGDRAW_BACKEND", "vulkan")
      putEnv("FIGDRAW_FORCE_OPENGL", "1")
      check runtimeForceOpenGlRequested() == true

  test "backend=opengl enables override":
    withCleanEnv proc() =
      putEnv("FIGDRAW_BACKEND", "opengl")
      delEnv("FIGDRAW_FORCE_OPENGL")
      check runtimeForceOpenGlRequested() == true

  test "backend=vulkan without force does not enable opengl override":
    withCleanEnv proc() =
      putEnv("FIGDRAW_BACKEND", "vulkan")
      delEnv("FIGDRAW_FORCE_OPENGL")
      check runtimeForceOpenGlRequested() == false
