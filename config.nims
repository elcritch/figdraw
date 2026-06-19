--nimcache:
  ".nimcache/"
--passc:
  "-Wno-incompatible-function-pointer-types"
--define:
  useMalloc
--define:
  release

import std/[strformat, strutils]
import std/os

when defined(macosx) and defined(figdraw.moltenvkBrew):
  let moltenVkPrefix = gorgeEx("brew --prefix molten-vk").output.strip()
  if moltenVkPrefix.len == 0:
    quit "figdraw.moltenvkBrew requires Homebrew molten-vk"
  switch("passL", "-Wl,-rpath," & moltenVkPrefix & "/lib")

when defined(linux):
  proc pkgConfigFlags(kind: string, packages: openArray[string]): string =
    for pkg in packages:
      let exists = gorgeEx("sh -c 'pkg-config --exists " & pkg & " && printf yes'").output.strip()
      if exists == "yes":
        let flags = gorgeEx("pkg-config --" & kind & " " & pkg).output.strip()
        if flags.len > 0:
          if result.len > 0:
            result.add ' '
          result.add flags

  # Optional deps
  when defined(figdraw.vulkan):
    let vulkanCflags = pkgConfigFlags("cflags", ["vulkan"])
    let vulkanLibs = pkgConfigFlags("libs", ["vulkan"])
    if vulkanCflags.len > 0:
      switch("passC", vulkanCflags)
    if vulkanLibs.len > 0:
      switch("passL", vulkanLibs)

  when defined(figdraw.harfbuzz):
    let shaperCflags = pkgConfigFlags("cflags", ["harfbuzz", "fribidi"])
    let shaperLibs = pkgConfigFlags("libs", ["harfbuzz", "fribidi"])
    if shaperCflags.len > 0:
      switch("passC", shaperCflags)
    if shaperLibs.len > 0:
      switch("passL", shaperLibs)

  # Deps that figdraw absolutely needs to even compile
  # source: painful amounts of trial and error
  const
    XorgDependencies = "x11-xcb xcb xcursor xkbcommon xrender"
    WaylandDependencies = "wayland-client wayland-egl wayland-egl-backend"
    AuxDependencies = "gl glesv2 egl"

  let linuxCflags =
    pkgConfigFlags("cflags", XorgDependencies.splitWhitespace() & WaylandDependencies.splitWhitespace() & AuxDependencies.splitWhitespace())
  let linuxLibs =
    pkgConfigFlags("libs", XorgDependencies.splitWhitespace() & WaylandDependencies.splitWhitespace() & AuxDependencies.splitWhitespace())
  if linuxCflags.len > 0:
    switch("passC", linuxCflags)
  if linuxLibs.len > 0:
    switch("passL", linuxLibs)

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
    if sessionType == "wayland":
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=1 "
    elif sessionType == "x11":
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=0 "
      result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=1 "
    else:
      if hasWaylandDisplay:
        result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=0 "
        result.add "XDG_SESSION_TYPE=wayland FIGDRAW_FORCE_OPENGL=1 "
      if hasX11Display:
        result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=0 "
        result.add "XDG_SESSION_TYPE=x11 FIGDRAW_FORCE_OPENGL=1 "
  else:
    @[""]

task test, "run unit test":
  let enableSdl2 =
    getEnv("FIGDRAW_TEST_SDL2").strip().toLowerAscii() in ["1", "true", "yes", "on"]

  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      if file.startsWith("tests/t") and file.endsWith(".nim"):
        nimExec("r", file, platform = platformArg)

  for file in listFiles("examples"):
    if file.startsWith("examples/windy_") and file.endsWith(".nim"):
      nimExec("c", file)
    elif file.startsWith("examples/siwin_") and file.endsWith(".nim"):
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
  proc compile(libName: string, flags = "") =
    exec "nim c -f " & flags & " --path:src -d:release " &
      " -d:gennyNim -d:gennyC -d:gennyPython " &
      " --app:lib --gc:arc --tlsEmulation:off --out:" & libName &
      " --outdir:src/figdraw/bindings/generated src/figdraw/bindings/bindings.nim"

  when defined(windows):
    compile "figdraw.dll"
  elif defined(macosx):
    compile "libfigdraw.dylib.arm",
      "--cpu:arm64 -l:'-target arm64-apple-macos11' -t:'-target arm64-apple-macos11'"
    compile "libfigdraw.dylib.x64",
      "--cpu:amd64 -l:'-target x86_64-apple-macos10.12' -t:'-target x86_64-apple-macos10.12'"
    exec "lipo src/figdraw/bindings/generated/libfigdraw.dylib.arm src/figdraw/bindings/generated/libfigdraw.dylib.x64 -output src/figdraw/bindings/generated/libfigdraw.dylib -create"
  else:
    compile "libfigdraw.so"
