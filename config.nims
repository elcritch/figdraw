--nimcache:".nimcache/"
--passc:"-Wno-incompatible-function-pointer-types"
--define:useMalloc
--define:release

import std/strutils
import std/os

proc nimExec(subcmd, file: string, extraFlags = "", platform = "") =
  let nimFlags = getEnv("NIMFLAGS").strip()
  var cmd: string
  cmd.add(platform)
  cmd.add("nim " & subcmd)
  cmd.add(" " & nimFlags)
  cmd.add(" " & extraFlags)
  cmd.add(" " & file)
  exec(cmd)

proc platforms(): seq[string] =
  when defined(linux) or defined(bsd):
    let
      sessionType = getEnv("XDG_SESSION_TYPE").toLowerAscii()
      hasWaylandDisplay = getEnv("WAYLAND_DISPLAY").len != 0
      hasX11Display = getEnv("DISPLAY").len != 0
    if hasWaylandDisplay or sessionType == "wayland":
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=1 "
    if hasX11Display or sessionType == "x11":
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=1 "
  else:
    @[""]

task test, "run unit test":
  let enableSdl2 =
    getEnv("FIGDRAW_TEST_SDL2").strip().toLowerAscii() in ["1", "true", "yes", "on"]

  for platformArg in platforms():
    if platformArg != "": echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if file.startsWith("tests/t") and file.endsWith(".nim"):
        nimExec("r", file, platform = platformArg)

  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      nimExec("c", file)
    elif file.startsWith("examples/sdl2_") and file.endsWith(".nim"):
      if enableSdl2:
        nimExec("c", file, "-d:figdraw.metal=off -d:figdraw.vulkan=off")
      else:
        echo "Skipping SDL2 example (set FIGDRAW_TEST_SDL2=1 to enable): ", file

task test_compile, "compile unit tests without running":
  for file in listFiles("tests"):
    if file.startsWith("tests/t") and file.endsWith(".nim"):
      nimExec("c", file)

task test_emscripten, "build emscripten examples":
  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      nimExec("c", file, "-d:emscripten")

task bindings, "Generate bindings":
  let includeSiwinShim =
    getEnv("FIGDRAW_BINDINGS_SIWINSHIM").strip().toLowerAscii() in
    ["1", "true", "yes", "on"]
  let siwinShimFlag = if includeSiwinShim: " -d:figdraw.bindings.siwinshim" else: ""

  proc compile(libName: string, flags = "") =
    exec "nim c -f " & flags &
      siwinShimFlag &
      " --path:src -d:release --app:lib --gc:arc --tlsEmulation:off --out:" & libName &
      " --outdir:bindings/generated bindings/bindings.nim"

  when defined(windows):
    compile "figdraw.dll"
  elif defined(macosx):
    compile "libfigdraw.dylib.arm",
      "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "libfigdraw.dylib.x64",
      "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec "lipo bindings/generated/libfigdraw.dylib.arm bindings/generated/libfigdraw.dylib.x64 -output bindings/generated/libfigdraw.dylib -create"
  else:
    compile "libfigdraw.so"
