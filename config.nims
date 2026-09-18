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
import src/figdraw/build/tasks

when defined(useNativeDynlib):
  switch("path", "bin")
  # The staged library is built with ARC; managed values crossing this ABI
  # must use the same memory manager in the consumer.
  switch("mm", "arc")

when defined(macosx) and defined(figdraw.moltenvkBrew):
  let moltenVkPrefix = gorgeEx("brew --prefix molten-vk").output.strip()
  if moltenVkPrefix.len == 0:
    quit "figdraw.moltenvkBrew requires Homebrew molten-vk"
  switch("passL", "-Wl,-rpath," & moltenVkPrefix & "/lib")

when defined(linux):
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

  let linuxCflags = pkgConfigFlags(
    "cflags",
    XorgDependencies.splitWhitespace() & WaylandDependencies.splitWhitespace() &
      AuxDependencies.splitWhitespace(),
  )
  let linuxLibs = pkgConfigFlags(
    "libs",
    XorgDependencies.splitWhitespace() & WaylandDependencies.splitWhitespace() &
      AuxDependencies.splitWhitespace(),
  )
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
      testRenderer = getEnv("FIGDRAW_TEST_RENDERER").strip().toLowerAscii()

    proc addPlatform(platformArgs: var seq[string], sessionType: string) =
      case testRenderer
      of "opengl":
        platformArgs.add("XDG_SESSION_TYPE=" & sessionType & " FIGDRAW_FORCE_OPENGL=1 ")
      of "vulkan":
        platformArgs.add("XDG_SESSION_TYPE=" & sessionType & " FIGDRAW_FORCE_OPENGL=0 ")
      else:
        platformArgs.add("XDG_SESSION_TYPE=" & sessionType & " FIGDRAW_FORCE_OPENGL=0 ")
        platformArgs.add("XDG_SESSION_TYPE=" & sessionType & " FIGDRAW_FORCE_OPENGL=1 ")

    if sessionType == "wayland":
      addPlatform(result, "wayland")
    elif sessionType == "x11":
      addPlatform(result, "x11")
    else:
      if hasWaylandDisplay:
        addPlatform(result, "wayland")
      if hasX11Display:
        addPlatform(result, "x11")
  else:
    @[""]

task test, "run unit test":
  let enableSdl2 =
    getEnv("FIGDRAW_TEST_SDL2").strip().toLowerAscii() in ["1", "true", "yes", "on"]
  var excludedTests: seq[string]
  when not defined(useNativeDynlib):
    excludedTests.add("tsiwin_redraw.nim")
  for testName in getEnv("FIGDRAW_TEST_EXCLUDE").split(','):
    let cleaned = testName.strip()
    if cleaned.len > 0:
      excludedTests.add(cleaned)

  var testRuns = 0
  for platformArg in platforms():
    if platformArg != "":
      echo "Running platform args: ", platformArg
    for file in listFiles("tests"):
      let name = file.extractFilename()
      if name.startsWith("t") and name.endsWith(".nim") and name notin excludedTests:
        inc testRuns
        nimExec("r", file, platform = platformArg)

  if testRuns == 0:
    quit "No test files were discovered"
  echo "Ran ", testRuns, " test files"

  for file in listFiles("examples"):
    let name = file.extractFilename()
    if name.startsWith("windy_") and name.endsWith(".nim"):
      nimExec("c", file)
    elif name.startsWith("siwin_") and name.endsWith(".nim"):
      if name == "siwin_shared_native.nim":
        echo "Skipping native shared example (run: nim native_shared_example)"
      else:
        nimExec("c", file)
    elif name.startsWith("sdl2_") and name.endsWith(".nim"):
      if enableSdl2:
        nimExec("c", file, "-d:figdraw.metal=off -d:figdraw.vulkan=off")
      else:
        echo "Skipping SDL2 example (set FIGDRAW_TEST_SDL2=1 to enable): ", file

task test_compile, "compile unit tests without running":
  var testCount = 0
  for file in listFiles("tests"):
    let name = file.extractFilename()
    let isNativeDynlibTest = name == "tsiwin_redraw.nim"
    if name.startsWith("t") and name.endsWith(".nim") and
        (not isNativeDynlibTest or defined(useNativeDynlib)):
      inc testCount
      nimExec("c", file)
  if testCount == 0:
    quit "No test files were discovered"
  echo "Compiled ", testCount, " test files"

task test_emscripten, "build emscripten examples":
  for file in listFiles("examples"):
    let name = file.extractFilename()
    if name.startsWith("windy_") and name.endsWith(".nim"):
      nimExec("c", file, "-d:emscripten")

task build_dynlib, "Stage native Nim dynlib artifacts in bin":
  nativeBuild.buildNativeDynlib()
  nativeBuild.stageNativeDynlib("bin")

task native_shared_example, "Stage the native dynlib and build the siwin example":
  nativeBuild.buildNativeDynlib()
  nativeBuild.stageNativeDynlib("bin")
  runNativeNim(
    [
      "c", "-d:release", "--mm:arc", "-d:useMalloc", "--path:bin",
      "--out:examples/siwin_shared_native", "examples/siwin_shared_native.nim",
    ]
  )
