import std/[math, os, unittest]

import figdraw/common/shared
import figdraw/windowing/siwinshim

suite "siwin scale":
  test "X11 logical size accounts for backing pixel scale":
    when defined(linux) or defined(bsd):
      block runNativeWindow:
        if getEnv("DISPLAY").len == 0:
          skip()
          break runNativeWindow

        defer:
          setFigUiScale(1.0'f32)

        let window = newSiwinWindow(
          size = ivec2(320'i32, 180'i32),
          fullscreen = false,
          title = "figdraw test: x11 scale",
        )
        try:
          if window.siwinDisplayServerName() != "x11":
            skip()
          else:
            check window.inputUsesBackingPixels()

            setFigUiScale(1.5'f32)
            let
              backing = window.backingSize()
              logical = window.logicalSize()
            check abs(logical.x * figUiScale() - backing.x.float32) < 0.01'f32
            check abs(logical.y * figUiScale() - backing.y.float32) < 0.01'f32

            discard window.configureUiScale()
            check figUiScale() == window.contentScale()
        finally:
          window.close()
    else:
      skip()
