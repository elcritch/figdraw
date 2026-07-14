version = "0.30.0"
author = "Jaremy Creechley"
description = "UI Engine for Nim"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.2"
requires "pixie >= 5.0.1"
requires "chroma >= 0.2.7"
requires "bumpy"
requires "stack_strings"
requires "chronicles >= 0.10.3"
requires "sdfy >= 0.8.1"
requires "nimsimd >= 1.2.5"
requires "variant"
requires "patty"
requires "supersnappy"
requires "opengl"
requires "vmath"

when defined(macosx):
  requires "https://github.com/elcritch/metalx >= 0.4.2 "
when defined(linux) or defined(bsd) or defined(windows):
  requires "https://github.com/planetis-m/vulkan#b223dc9"

feature "harfbuzz":
  requires "gh:elcritch/harfbuzzy >= 0.2.2"
feature "lottie":
  requires "jsony"
feature "sdl2":
  requires "sdl2"
feature "windy":
  requires "windy"
feature "surfer":
  requires "surfer >= 0.2.5"
  requires "xkb#b4d50f4cccad1cd9e39d2f5a5e1fef2710edcc31"
  # TODO: Put this in surfer's manifest.
feature "siwin":
  requires "siwin >= 1.0.1"
feature "vulkan":
  requires "https://github.com/planetis-m/vulkan#b223dc9"
feature "metal":
  requires "https://github.com/elcritch/metalx#head"
feature "sharedlib":
  requires "gh:treeform/genny#81d9659"
  requires "gh:elcritch/binny >= 0.4.2"

import std/os

task nativeDynlib, "Build and stage the native Nim dynamic library":
  let compiler = getEnv("FIGDRAW_NATIVE_NIM", getHomeDir() & "/projs/nims/Nim/bin/nim")
  exec compiler.quoteShell & " native_dynlib"
