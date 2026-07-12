import std/[os, strutils]
import binny/native_dynlib

if paramCount() notin 4 .. 5:
  quit "usage: generate_native_bindings NIMCACHE SOURCE MANIFEST OUTPUT [LIBRARY]"

let libraryOverride =
  if paramCount() == 5:
    paramStr(5)
  else:
    ""
let config =
  initNativeBindingsConfig(paramStr(2), paramStr(3), paramStr(1), libraryOverride)
let outputPath = paramStr(4)
discard config.writeNativeBindings(outputPath)

var bindings = outputPath.readFile()
bindings =
  bindings.replace("const nativeLibrary* =", "const nativeLibrary* {.strdefine.} =")
outputPath.writeFile(bindings)
