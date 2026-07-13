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

when defined(useNativeDynlib):
  switch("path", "bin")

when defined(macosx) and defined(figdraw.moltenvkBrew):
  let moltenVkPrefix = gorgeEx("brew --prefix molten-vk").output.strip()
  if moltenVkPrefix.len == 0:
    quit "figdraw.moltenvkBrew requires Homebrew molten-vk"
  switch("passL", "-Wl,-rpath," & moltenVkPrefix & "/lib")

when defined(linux):
  proc pkgConfigFlags(kind: string, packages: openArray[string]): string =
    for pkg in packages:
      let exists =
        gorgeEx("sh -c 'pkg-config --exists " & pkg & " && printf yes'").output.strip()
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

proc unsupportedNativeDynlibPath(): string =
  quit "native Nim dynlibs currently support macOS, Linux, and BSD"

# Invoke this task with a compiler that supports the experimental native ABI.
task native_bindings, "Build native Nim dynlib and generate Binny bindings":
  let
    compiler = getCurrentCompilerExe()
    cacheDir = ".nimcache/native_figdraw"
    producer = "src/figdraw/bindings/native_bindings.nim"
    generator = "src/figdraw/bindings/generate_native_bindings.nim"
    manifest = cacheDir / "libfigdraw_native.abi.nif"
    bindings = cacheDir / "figdraw_native_abi.nim"
    library =
      when defined(macosx):
        cacheDir / "libfigdraw_native.dylib"
      elif defined(linux) or defined(bsd):
        cacheDir / "libfigdraw_native.so"
      else:
        unsupportedNativeDynlibPath()

  exec compiler & " c -f --experimental:abi --emitBif:on --app:lib --mm:orc" &
    " -d:useMalloc -d:figdrawNativeDynlib -d:release" &
    " --path:src --path:deps/siwin/src" & " --nimcache:" & cacheDir & " --out:" & library &
    " " & producer
  exec compiler & " r -d:release --path:../binny" & " --nimcache:" &
    cacheDir / "generator" & " " & generator & " " & cacheDir & " " & producer & " " &
    manifest & " " & bindings

task native_dynlib, "Stage native Nim dynlib artifacts in bin":
  let
    compiler = getCurrentCompilerExe()
    cacheDir = ".nimcache/native_figdraw"
    producer = "src/figdraw/bindings/native_bindings.nim"
    generator = "src/figdraw/bindings/generate_native_bindings.nim"
    manifest = cacheDir / "libfigdraw_native.abi.nif"
    bindings = "bin" / "figdraw_native_abi.nim"
    libraryName =
      when defined(macosx):
        "libfigdraw_native.dylib"
      elif defined(linux) or defined(bsd):
        "libfigdraw_native.so"
      else:
        unsupportedNativeDynlibPath()
    stagedLibrary = "bin" / libraryName

  exec compiler & " native_bindings"
  exec "mkdir -p bin"
  exec "cp " & (cacheDir / libraryName).quoteShell() & " " & stagedLibrary.quoteShell()
  exec "cp " & manifest.quoteShell() & " " &
    ("bin" / manifest.extractFilename()).quoteShell()
  exec compiler & " r -d:release --path:../binny" & " --nimcache:" &
    cacheDir / "generator" & " " & generator & " " & cacheDir & " " & producer & " " &
    manifest & " " & bindings & " " & stagedLibrary

task native_shared_example, "Build the native Nim siwin shared example":
  let compiler = getCurrentCompilerExe()
  exec compiler & " native_bindings"
  exec compiler & " c --mm:orc -d:useMalloc --path:.nimcache/native_figdraw" &
    " --out:examples/siwing_shared_native examples/siwing_shared_native.nim"
