import std/[os, strutils]

import binny/native_dynlib/build
export build

when defined(linux):
  const
    XorgDependencies* = "x11-xcb xcb xcursor xkbcommon xrender"
    WaylandDependencies* = "wayland-client wayland-egl wayland-egl-backend"
    AuxDependencies* = "gl glesv2 egl"

  proc pkgConfigFlags*(kind: string, packages: openArray[string]): string =
    for pkg in packages:
      let exists =
        gorgeEx("sh -c 'pkg-config --exists " & pkg & " && printf yes'").output.strip()
      if exists == "yes":
        let flags = gorgeEx("pkg-config --" & kind & " " & pkg).output.strip()
        if flags.len > 0:
          if result.len > 0:
            result.add ' '
          result.add flags

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
  nativeBindings = "bin/figdraw_native_abi.nim"

var nativeBuild* = initNativeDynlibBuildConfig(
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
      "QuartzCore", "-framework", "Security", "-lobjc", "-lc++",
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

proc nativeCommand*(arguments: openArray[string]): string =
  for index, argument in arguments:
    if index > 0:
      result.add ' '
    result.add argument.quoteShell()

proc runNativeNim*(arguments: openArray[string]) =
  var command = @[nativeBuild.compiler]
  command.add arguments
  exec nativeCommand(command)
