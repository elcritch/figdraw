import std/unittest
when defined(linux) or defined(bsd):
  import std/os

when defined(useNativeDynlib):
  import figdraw_native_abi
  from pkg/vmath import ivec2, x, y

suite "native dynlib UI scale":
  test "reports logical dimensions instead of backing pixels":
    when defined(useNativeDynlib):
      block runWindow:
        when defined(linux) or defined(bsd):
          if getEnv("DISPLAY").len == 0 and getEnv("WAYLAND_DISPLAY").len == 0:
            skip()
            break runWindow

        let
          window = newSiwinWindow(
            ivec2(320, 220),
            false,
            "figdraw native scale test",
            true,
            0,
            true,
            false,
            false,
          )
          app = newFigSiwinApp(window, 192, 1.0)
          autoScale = configureUiScale(window, "HDI")
        require not app.isNil
        require not app.renderer.isNil
        var
          resizeCount = 0
          resizeSize: IVec2
          closeCount = 0
        window.eventsHandler = WindowEventsHandler(
          onResize: proc(event: ResizeEvent) =
            inc resizeCount
            resizeSize = event.size,
          onClose: proc(event: CloseEvent) =
            inc closeCount
          ,
        )
        try:
          firstStep(window, false)
          refreshUiScale(window, autoScale)

          `minSize=`(window, ivec2(100, 80))
          `maxSize=`(window, ivec2(1280, 720))
          check minSize(window).x == 100
          check minSize(window).y == 80
          check maxSize(window).x == 1280
          check maxSize(window).y == 720
          `title=`(window, "direct Siwin setters")
          `size=`(window, ivec2(400, 280))
          for _ in 0 ..< 20:
            step(window)
            if resizeCount > 0:
              break
          check resizeCount > 0
          check resizeSize.x > 0
          check resizeSize.y > 0
          check closeCount == 0

          let logical = logicalSize(window)
          if inputUsesBackingPixels(window):
            let
              backing = backingSize(window)
              scale = max(contentScale(window), 0.0001'f32)
            check abs(logical.x - backing.x.float32 / scale) < 0.01'f32
            check abs(logical.y - backing.y.float32 / scale) < 0.01'f32
          else:
            let dimensions = size(window)
            check logical.x == dimensions.x.float32
            check logical.y == dimensions.y.float32
        finally:
          # Release consumer closures before closing the producer-owned window.
          window.eventsHandler = WindowEventsHandler()
          close(window)
    else:
      skip()
