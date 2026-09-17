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
when defined(feature.figdraw.sharedlib):
  import binny/native_dynlib/build

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

proc requestedDefine(name: string): tuple[found: bool, value: string] =
  let prefixes = ["-d:" & name, "--define:" & name]
  for index in 0 ..< paramCount():
    let argument = paramStr(index)
    for prefix in prefixes:
      if argument == prefix:
        return (true, "true")
      if argument.startsWith(prefix & "="):
        return (true, argument[(prefix.len + 1) .. ^1])

  # NIMFLAGS is used by Atlas and by a few local build scripts. NimScript's
  # parameter list contains command-line switches, but not flags injected
  # through this environment variable.
  for argument in getEnv("NIMFLAGS").splitWhitespace():
    for prefix in prefixes:
      if argument == prefix:
        return (true, "true")
      if argument.startsWith(prefix & "="):
        return (true, argument[(prefix.len + 1) .. ^1])

proc addProducerDefine(
    args: var seq[string], name: string, configured, defaultValue: bool
): bool =
  let requested = requestedDefine(name)
  if requested.found:
    try:
      result = requested.value.parseBool()
    except ValueError as exc:
      quit "invalid value for " & name & ": " & exc.msg
    args.add("-d:" & name & "=" & requested.value)
  elif configured:
    # A bare define supplied by a parent config has no value available to
    # NimScript. It has Nim's normal true semantics.
    result = true
    args.add("-d:" & name & "=true")
  else:
    result = defaultValue

let
  nativeBackend = getEnv("FIGDRAW_NATIVE_BACKEND", "c").strip().toLowerAscii()
  nativeProducer = "src/figdraw/bindings/native_bindings.nim"
  nativeBindings =
    ".nimcache/native_figdraw" / nativeBackend / "figdraw_native_abi.nim"

var nativeBuild = initNativeDynlibBuildConfig(
  nativeProducer,
  "libfigdraw_native",
  buildRoot = ".nimcache/native_figdraw",
  bindingsPath = nativeBindings,
  exportConfigPath = "src/figdraw/bindings/native_dynlib.json",
  backend = nativeBackend,
)

nativeBuild.nimArgs =
  @["--mm:arc", "-d:useMalloc", "-d:release", "--path:src", "--path:deps/siwin/src"]


let
  defaultMetal = defined(macosx)
  defaultVulkan = defined(bsd) or defined(linux) or defined(windows)
  defaultOpenGl =
    when defined(linux) or defined(cpu32):
      true
    else:
      not (defined(macosx) or defined(bsd) or defined(windows))
  producerMetal = nativeBuild.nimArgs.addProducerDefine(
    "figdraw.metal", defined(figdraw.metal), defaultMetal
  )
  producerVulkan = nativeBuild.nimArgs.addProducerDefine(
    "figdraw.vulkan", defined(figdraw.vulkan), defaultVulkan
  )
  producerOpenGl = nativeBuild.nimArgs.addProducerDefine(
    "figdraw.opengl", defined(figdraw.opengl), defaultOpenGl
  )
discard nativeBuild.nimArgs.addProducerDefine(
  "figdraw.openglFallback",
  defined(figdraw.openglFallback),
  (producerMetal or producerVulkan) and not producerOpenGl,
)
nativeBuild.libraryNameStrdefine = true
when defined(macosx):
  nativeBuild.linkerArgs =
    @[
      "-framework", "AppKit", "-framework", "CoreFoundation", "-framework",
      "CoreGraphics", "-framework", "Foundation", "-framework", "Metal", "-framework",
      "QuartzCore", "-framework", "Security", "-lobjc",
    ]
elif defined(linux):
  nativeBuild.linkerArgs = pkgConfigFlags(
      "libs",
      XorgDependencies.splitWhitespace() & WaylandDependencies.splitWhitespace() &
        AuxDependencies.splitWhitespace(),
    )
    .splitWhitespace()
  if producerVulkan and not producerOpenGl:
    nativeBuild.linkerArgs.add pkgConfigFlags("libs", ["vulkan"]).splitWhitespace()
  when defined(figdraw.harfbuzz):
    nativeBuild.linkerArgs.add(
      pkgConfigFlags("libs", ["harfbuzz", "fribidi"]).splitWhitespace()
    )

proc nativeCommand(arguments: openArray[string]): string =
  for index, argument in arguments:
    if index > 0:
      result.add ' '
    result.add argument.quoteShell()

proc runNativeNim(arguments: openArray[string]) =
  var command = @[nativeBuild.compiler]
  command.add arguments
  exec nativeCommand(command)

task native_bindings, "Build native Nim dynlib and generate Binny bindings":
  when not defined(feature.figdraw.sharedlib):
    {.error: "requires sharedlib feature".}
  nativeBuild.buildNativeDynlibAndBindings()

task native_dynlib, "Stage native Nim dynlib artifacts in bin":
  when not defined(feature.figdraw.sharedlib):
    {.error: "requires sharedlib feature".}
  nativeBuild.buildNativeDynlib()
  nativeBuild.stageNativeDynlib("bin")

task native_shared_example, "Stage the native dynlib and build the siwin example":
  when not defined(feature.figdraw.sharedlib):
    {.error: "requires sharedlib feature".}
  nativeBuild.buildNativeDynlib()
  nativeBuild.stageNativeDynlib("bin")
  runNativeNim(
    [
      "c", "-d:release", "--mm:arc", "-d:useMalloc", "--path:bin",
      "--out:examples/siwin_shared_native", "examples/siwin_shared_native.nim",
    ]
  )
