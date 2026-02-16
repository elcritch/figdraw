version       = "0.19.2"
author        = "Jaremy Creechley"
description   = "UI Engine for Nim"
license       = "MIT"
srcDir        = "src"

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
  requires "https://github.com/planetis-m/vulkan#master"

feature "lottie":
  requires "jsony"

feature "sdl2":
  requires "sdl2"

feature "windy":
  requires "windy"
feature "surfer":
  requires "https://github.com/nim-windowing/surfer"
feature "siwin":
  requires "siwin#master"

feature "vulkan":
  requires "https://github.com/planetis-m/vulkan#b223dc9"
feature "metal":
  requires "https://github.com/elcritch/metalx#head"


