--nimcache:".nimcache/"
--passc:"-Wno-incompatible-function-pointer-types"
--define:useMalloc

import std/strutils

task test, "run unit test":
  for file in listFiles("tests"):
    if file.startsWith("tests/t") and file.endsWith(".nim"):
      exec("nim r " & file)

  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      exec("nim c " & file)
    elif file.startsWith("examples/sdl2_") and file.endsWith(".nim"):
      exec("nim c -d:figdraw.metal=off -d:figdraw.vulkan=off " & file)

task test_emscripten, "build emscripten examples":
  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      exec("nim c -d:emscripten " & file)

