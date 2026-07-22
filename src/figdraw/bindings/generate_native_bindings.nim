import std/[os, strutils]
import binny/native_dynlib

if paramCount() notin 5 .. 6:
  quit "usage: generate_native_bindings NIMCACHE SOURCE_ROOT SOURCE OUTPUT LIBRARY [CONFIG]"

let
  exportConfig =
    if paramCount() == 6:
      loadNativeExportConfig(paramStr(6))
    else:
      NativeExportConfig()
  config = initBifNativeBindingsConfig(
    paramStr(3), paramStr(1), paramStr(5), paramStr(2), exportConfig
  )
  outputPath = paramStr(4)
discard config.writeNativeBindings(outputPath)

var bindings = outputPath.readFile()
bindings =
  bindings.replace("const nativeLibrary* =", "const nativeLibrary* {.strdefine.} =")
outputPath.writeFile(bindings)
