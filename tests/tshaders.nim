import std/unittest

import figdraw/opengl/shaders

suite "OpenGL shader profile selection":
  test "detects desktop OpenGL":
    check not usesGlslEsShaderProfile(
      "4.6 (Core Profile) Mesa 26.1.5", "4.60"
    )

  test "detects OpenGL ES from the context version":
    check usesGlslEsShaderProfile(
      "OpenGL ES 3.2 Mesa 26.1.5", "OpenGL ES GLSL ES 3.20"
    )

  test "detects OpenGL ES from the shading language version":
    check usesGlslEsShaderProfile("unknown", "OpenGL ES GLSL ES 1.00")

  test "matches version markers case insensitively":
    check usesGlslEsShaderProfile("OPENGL ES 2.0", "GLSL ES 1.0")
