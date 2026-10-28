version = "0.46.3"
author = "Jaremy Creechley"
description = "UI Engine for Nim"
license = "MIT"
srcDir = "src"

# Dependencies
requires "nim >= 2.2"
requires "sigils >= 0.31.0"
requires "threading >= 0.2.1"
requires "pixie >= 5.0.1"
requires "gh:elcritch/harfbuzzy >= 0.6.0[runtime]"
requires "chroma >= 0.2.7"
requires "bumpy"
requires "stack_strings"
requires "chronicles >= 0.10.3"
requires "sdfy >= 0.8.5"
requires "nimsimd >= 1.2.5"
requires "variant"
requires "patty"
requires "supersnappy"
requires "opengl"
requires "vmath"

when defined(macosx):
  requires "https://github.com/elcritch/metalx >= 0.4.2 "
when defined(linux) or defined(bsd) or defined(windows):
  requires "https://github.com/elcritch/vulkan#0fc8dd2"

feature "harfbuzz":
  discard # Kept for compatibility with existing Atlas configurations.
feature "textBackendHarfbuzzy":
  discard
feature "lottie":
  requires "jsony"
feature "sdl2":
  requires "sdl2"
feature "windy":
  requires "windy"
  # Typed query iterators avoid ambiguous converter overloads on Nim devel.
  requires "gh:elcritch/urlly#61cacc8436a377151b6ebdc66e112d4adbce05c6"
feature "surfer":
  requires "surfer >= 0.2.5"
  requires "xkb#b4d50f4cccad1cd9e39d2f5a5e1fef2710edcc31"
  # TODO: Put this in surfer's manifest.
feature "siwin":
  # Includes native Win32 handles and the software-present toggle.
  requires "gh:levovix0/siwin#5827ee9dadb5e2597db85375e0e87b8a2272174b"
feature "uirelays":
  requires "gh:elcritch/uirelays#feat/rgba-alpha"
feature "vulkan":
  requires "https://github.com/elcritch/vulkan#0fc8dd2"
feature "metal":
  requires "https://github.com/elcritch/metalx#head"
feature "sharedlib":
  requires "gh:elcritch/binny >= 0.5.22"

when defined(feature.figdraw.sharedlib):
  import std/os
  when fileExists("src/figdraw/build/tasks.nim"):
    import src/figdraw/build/tasks
  else:
    import figdraw/build/tasks

  task build_dynlib, "Stage native Nim dynlib artifacts in bin":
    buildAndStageNativeDynlib()

  task native_shared_example, "Stage the native dynlib and build the siwin example":
    buildAndStageNativeDynlib()
    runNativeNim(
      [
        "c", "-d:release", "--mm:arc", "-d:useMalloc", "--path:bin",
        "--out:examples/siwin_shared_native", "examples/siwin_shared_native.nim",
      ]
    )
