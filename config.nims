--nimcache:
  ".nimcache/"
--passc:
  "-Wno-incompatible-function-pointer-types"
--define:
  useMalloc
--define:
  release

import std/[algorithm, json, strformat, strutils]
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
  quit "native Nim dynlibs currently support macOS, Linux, and FreeBSD"

let
  nativeCompiler = getCurrentCompilerExe()
  nativeBackend = getEnv("FIGDRAW_NATIVE_BACKEND", "c").strip().toLowerAscii()
  nativeCacheDir = ".nimcache/native_figdraw" / nativeBackend
  nativeProducerCache = nativeCacheDir / "producer"
  nativeToolCache = nativeCacheDir / "tool"
  nativeGeneratorCache = nativeCacheDir / "generator"
  nativeProducer = "src/figdraw/bindings/native_bindings.nim"
  nativeSourceRoot = nativeProducer.parentDir
  nativeExportConfig = nativeSourceRoot / "native_dynlib.json"
  nativeGenerator = "src/figdraw/bindings/generate_native_bindings.nim"
  nativeToolSource = "../binny/tools/native_dynlib.nim"
  nativeTool = nativeToolCache / "native_dynlib"
  nativeCRoot = nativeProducerCache / "binny_native_root.nim"
  nativeGeneratorBinary = nativeGeneratorCache / "generate_native_bindings"
  nativeBackendOutput = nativeProducerCache / "figdraw_native_backend"
  nativePrivateArchive = nativeCacheDir / "libfigdraw_native.private.a"
  nativePublicArchive = nativeCacheDir / "libfigdraw_native.a"
  nativeExportList = nativeCacheDir / "libfigdraw_native.exports"
  nativeLibraryName =
    when defined(macosx):
      "libfigdraw_native.dylib"
    elif defined(linux) or defined(freebsd):
      "libfigdraw_native.so"
    else:
      unsupportedNativeDynlibPath()
  nativeLibrary = nativeCacheDir / nativeLibraryName
  nativeBindings = nativeCacheDir / "figdraw_native_abi.nim"

proc nativeCommand(args: openArray[string]): string =
  for index, arg in args:
    if index > 0:
      result.add ' '
    result.add arg.quoteShell()

proc runNativeCommand(args: openArray[string]) =
  exec nativeCommand(args)

proc runNativeNim(args: openArray[string]) =
  var command = @[nativeCompiler]
  command.add args
  runNativeCommand(command)

proc compileNativeProducer(source: string, force = false) =
  if nativeBackend notin ["c", "ic"]:
    quit "FIGDRAW_NATIVE_BACKEND must be either 'c' or 'ic'"
  var arguments =
    @[
      nativeBackend,
      "--genBif:on",
      "--app:staticlib",
      "--mm:orc",
      "-d:useMalloc",
      "-d:release",
      "--path:src",
      "--path:deps/siwin/src",
      "--nimcache:" & nativeProducerCache,
      "--out:" & nativeBackendOutput,
    ]
  if force:
    arguments.add "-f"
  when defined(linux) or defined(freebsd):
    if nativeBackend == "c":
      arguments.add "--passC:-fPIC"
  arguments.add source
  runNativeNim(arguments)

proc buildNativeTool() =
  if not fileExists(nativeToolSource):
    quit "the Atlas-linked Binny checkout is missing: " & nativeToolSource
  runNativeNim(
    [
      "c",
      "-d:release",
      "--hints:off",
      "--path:../binny",
      "--nimcache:" & nativeToolCache,
      "--out:" & nativeTool,
      nativeToolSource,
    ]
  )

proc archiveNativeObjects() =
  var objects: seq[string]
  if nativeBackend == "c":
    let buildDescription = parseJson(readFile(nativeBackendOutput & ".json"))
    for objectNode in buildDescription["link"]:
      let objectPath = objectNode.getStr()
      if objectPath.endsWith(".o") and objectPath notin objects:
        objects.add objectPath
  else:
    for objectPath in listFiles(nativeProducerCache):
      if objectPath.endsWith(".o"):
        objects.add objectPath
  objects.sort()
  if objects.len == 0:
    quit "the native producer backend emitted no object files"
  var command =
    when defined(macosx):
      @["/usr/bin/libtool", "-static", "-o", nativePrivateArchive]
    elif defined(linux) or defined(freebsd):
      @["ar", "-rcs", nativePrivateArchive]
    else:
      @[unsupportedNativeDynlibPath()]
  command.add objects
  runNativeCommand(command)

proc expectedNativeExports(): seq[string] =
  var inGlobalSection = false
  for line in nativeExportList.readFile().splitLines:
    let value = line.strip()
    when defined(macosx):
      if value.len > 0:
        result.add value
    elif defined(linux) or defined(freebsd):
      if value == "global:":
        inGlobalSection = true
      elif value == "local:":
        inGlobalSection = false
      elif inGlobalSection and value.endsWith(";"):
        result.add value[0 ..< value.high].strip()

proc verifyNativeExports() =
  let command =
    when defined(macosx):
      @["/usr/bin/nm", "-gU", nativeLibrary]
    elif defined(linux) or defined(freebsd):
      @["nm", "-D", "--defined-only", nativeLibrary]
    else:
      @[unsupportedNativeDynlibPath()]
  let (output, exitCode) = gorgeEx(nativeCommand(command))
  if exitCode != 0:
    quit "nm failed for the generated native library:\n" & output
  var actual: seq[string]
  for line in output.splitLines:
    let fields = line.splitWhitespace()
    if fields.len > 0:
      actual.add fields[^1]
  actual.sort()
  var expected = expectedNativeExports()
  expected.sort()
  if actual != expected:
    quit "native library exports do not match the BIF-derived export list"

proc buildNativeProducer() =
  buildNativeTool()
  compileNativeProducer(nativeProducer)
  runNativeCommand(
    [
      nativeTool,
      "prepare",
      nativeProducerCache,
      nativeSourceRoot,
      nativeProducer,
      nativeCRoot,
      "--config:" & nativeExportConfig,
    ]
  )
  if nativeBackend == "c":
    compileNativeProducer(nativeCRoot, force = true)
  else:
    compileNativeProducer(nativeProducer)
  runNativeCommand(
    [
      nativeTool,
      "exports",
      nativeProducerCache,
      nativeSourceRoot,
      nativeProducer,
      nativeLibrary,
      nativeExportList,
      "--config:" & nativeExportConfig,
    ]
  )
  when defined(linux) or defined(freebsd):
    if nativeBackend == "ic":
      runNativeCommand([nativeTool, "pic", nativeProducerCache])
  archiveNativeObjects()
  runNativeCommand(
    [nativeTool, "promote", nativePrivateArchive, nativePublicArchive, nativeExportList]
  )
  runNativeCommand(
    block:
      var command =
        @[nativeTool, "link", nativePublicArchive, nativeLibrary, nativeExportList]
      when defined(macosx):
        command.add [
          "-framework", "AppKit", "-framework", "CoreFoundation", "-framework",
          "CoreGraphics", "-framework", "Foundation", "-framework", "Metal",
          "-framework", "QuartzCore", "-framework", "Security", "-lobjc",
        ]
      command
  )
  verifyNativeExports()

proc generateNativeBindings(outputPath, libraryPath: string) =
  runNativeNim(
    [
      "c",
      "-d:release",
      "--hints:off",
      "--path:../binny",
      "--nimcache:" & nativeGeneratorCache,
      "--out:" & nativeGeneratorBinary,
      nativeGenerator,
    ]
  )
  runNativeCommand(
    [
      nativeGeneratorBinary, nativeProducerCache, nativeSourceRoot, nativeProducer,
      outputPath, libraryPath, nativeExportConfig,
    ]
  )

task native_bindings, "Build native Nim dynlib and generate Binny bindings":
  buildNativeProducer()
  generateNativeBindings(nativeBindings, nativeLibrary)

task native_dynlib, "Stage native Nim dynlib artifacts in bin":
  let
    stagedLibrary = "bin" / nativeLibraryName
    stagedBindings = "bin" / "figdraw_native_abi.nim"
  buildNativeProducer()
  runNativeCommand(["mkdir", "-p", "bin"])
  runNativeCommand(["cp", nativeLibrary, stagedLibrary])
  generateNativeBindings(stagedBindings, stagedLibrary)

task native_shared_example, "Build the native Nim siwin shared example":
  buildNativeProducer()
  generateNativeBindings(nativeBindings, nativeLibrary)
  runNativeNim(
    [
      "c",
      "-d:release",
      "--mm:arc",
      "-d:useMalloc",
      "--path:" & nativeCacheDir,
      "--out:examples/siwing_shared_native",
      "examples/siwing_shared_native.nim",
    ]
  )
