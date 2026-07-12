import std/os
import binny/native_dynlib

if paramCount() != 4:
  quit "usage: generate_native_bindings NIMCACHE SOURCE MANIFEST OUTPUT"

let config = initNativeBindingsConfig(paramStr(2), paramStr(3), paramStr(1))
discard config.writeNativeBindings(paramStr(4))
