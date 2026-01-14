version       = "0.1.0"
author        = "Jaremy Creechley"
description   = "UI Engine for Nim"
license       = "MIT"
srcDir        = "src"

# Dependencies

requires "nim >= 2.0.10"
requires "pixie >= 5.0.1"
requires "chroma >= 0.2.7"
requires "bumpy"
requires "stack_strings"
requires "chronicles >= 0.10.3"
requires "https://github.com/elcritch/sdfy >= 0.7.7"
requires "nimsimd >= 1.2.5"
requires "https://github.com/elcritch/windex"
requires "shady"
requires "variant"
requires "patty"
requires "supersnappy"

feature "siwin":
  requires "siwin"

feature "reference":
  requires "https://github.com/elcritch/figuro"
  requires "fidget"

requires "sdl2"

