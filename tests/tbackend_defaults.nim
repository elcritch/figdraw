import std/unittest

import figdraw/commons

when (defined(linux) or defined(cpu32)) and not defined(figdraw.opengl):
  static:
    doAssert UseOpenGlBackend
    doAssert not UseVulkanBackend
    doAssert not UseMetalBackend

suite "renderer backend defaults":
  test "enables exactly one backend":
    check ord(UseOpenGlBackend) + ord(UseVulkanBackend) + ord(UseMetalBackend) == 1

  when (defined(linux) or defined(cpu32)) and not defined(figdraw.opengl):
    test "prefers OpenGL on Linux and 32-bit targets":
      check UseOpenGlBackend
