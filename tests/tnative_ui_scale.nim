import std/unittest
when defined(linux) or defined(bsd):
  import std/os

when defined(useNativeDynlib):
  import figdraw_native_abi

suite "native dynlib UI scale":
  test "reports logical dimensions instead of backing pixels":
    when defined(useNativeDynlib):
      block runWindow:
        when defined(linux) or defined(bsd):
          if getEnv("DISPLAY").len == 0 and getEnv("WAYLAND_DISPLAY").len == 0:
            skip()
            break runWindow

        let app = newFigSiwinApp(
          320, 220, "figdraw native scale test", 192, 1.0, false, true, 0, true, false,
          false,
        )
        require not app.isNil
        try:
          firstStep(app, false)
          siwinRefreshUiScale(app)

          let logical = siwinLogicalSize(app)
          if siwinInputUsesBackingPixels(app):
            let
              backing = siwinBackingSize(app)
              scale = max(siwinUiScale(app), 0.0001'f32)
            check abs(logical.w - backing.w.float32 / scale) < 0.01'f32
            check abs(logical.h - backing.h.float32 / scale) < 0.01'f32
          else:
            let size = siwinWindowSize(app)
            check logical.w == size.w.float32
            check logical.h == size.h.float32
        finally:
          close(app)
    else:
      skip()
