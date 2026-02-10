--nimcache:".nimcache/"
--passc:"-Wno-incompatible-function-pointer-types"
--define:useMalloc

import std/strutils
import std/os

proc nimExec(subcmd, file: string, extraFlags = "") =
  let nimFlags = getEnv("NIMFLAGS").strip()
  var cmd = "nim " & subcmd
  cmd.add(" " & nimFlags)
  cmd.add(" " & extraFlags)
  cmd.add(" " & file)
  exec(cmd)

task test, "run unit test":
  for file in listFiles("tests"):
    if file.startsWith("tests/t") and file.endsWith(".nim"):
      nimExec("r", file)

  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      nimExec("c", file)
    elif file.startsWith("examples/sdl2_") and file.endsWith(".nim"):
      nimExec("c", file, "-d:figdraw.metal=off -d:figdraw.vulkan=off")

task test_compile, "compile unit tests without running":
  for file in listFiles("tests"):
    if file.startsWith("tests/t") and file.endsWith(".nim"):
      nimExec("c", file)

task test_emscripten, "build emscripten examples":
  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      nimExec("c", file, "-d:emscripten")
