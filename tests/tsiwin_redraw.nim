import std/unittest
when defined(linux) or defined(bsd):
  import std/os

when defined(useNativeDynlib):
  import figdraw/dynlib
  from figdraw_native_abi import nil
else:
  import figdraw
  import figdraw/windowing/siwinshim

proc renderTree(size: Vec2): Renders =
  result = newRenders()
  discard result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, size.x, size.y),
      fill: rgba(40, 90, 180, 255),
    ),
  )

proc closeWindow(window: Window) =
  if window.opened:
    window.close()

suite "siwin redraw":
  when defined(useNativeDynlib):
    test "direct renderer exports retain ownership and desired text flags":
      block runWindow:
        when defined(linux) or defined(bsd):
          if getEnv("DISPLAY").len == 0 and getEnv("WAYLAND_DISPLAY").len == 0:
            skip()
            break runWindow

        let window = newSiwinWindow(size = ivec2(160, 120), title = "direct renderer")
        try:
          var app = newFigSiwinApp(window, 192, 1.0)
          require not app.isNil
          let renderer = app.renderer
          require not renderer.isNil
          block:
            let appAlias = app
            app = nil
            check appAlias.renderer == renderer
          # Both app references have gone out of scope; the renderer owns its state.
          check renderer.backendState.window == window
          check renderer.backendName() == backendName(renderer.backendKind())

          for enabled in [false, true, false]:
            # Metal stores desired flags for fallback, but has no active text toggles.
            let expected = enabled and renderer.backendKind() != rbMetal
            figdraw_native_abi.setTextLcdFiltering(renderer, enabled)
            figdraw_native_abi.setTextSubpixelPositioning(renderer, enabled)
            figdraw_native_abi.setTextSubpixelGlyphVariants(renderer, enabled)
            check figdraw_native_abi.textLcdFiltering(renderer) == expected
            check figdraw_native_abi.textSubpixelPositioning(renderer) == expected
            check figdraw_native_abi.textSubpixelGlyphVariants(renderer) == expected
            var desiredFlags = 0
            for name, value in fieldPairs(renderer[]):
              when name in [
                "textLcdFilteringDesired", "textSubpixelPositioningDesired",
                "textSubpixelGlyphVariantsDesired",
              ]:
                check value == enabled
                inc desiredFlags
            check desiredFlags == 3
        finally:
          closeWindow(window)

    test "direct icon overloads support borrowed pixels and clearing":
      block runWindow:
        when defined(linux) or defined(bsd):
          if getEnv("DISPLAY").len == 0 and getEnv("WAYLAND_DISPLAY").len == 0:
            skip()
            break runWindow

        let window = newSiwinWindow(size = ivec2(160, 120), title = "figdraw icon test")
        try:
          let
            image = newImage(2, 2)
            iconColor = rgba(64, 32, 16, 255)
          image.fill(iconColor)
          let buffer: PixelBuffer = image
          figdraw_native_abi.`icon=`(window, buffer)
          check image[0, 0] == iconColor
          figdraw_native_abi.`icon=`(window, nil)

          window.icon = image
          check image[0, 0] == iconColor
          window.icon = newImage(1, 1)
          window.icon = Image()
          window.icon = Image(nil)
          window.icon = nil
        finally:
          closeWindow(window)

  test "resize dispatches a redraw using the new logical size":
    block runWindow:
      when defined(linux) or defined(bsd):
        if getEnv("DISPLAY").len == 0 and getEnv("WAYLAND_DISPLAY").len == 0:
          skip()
          break runWindow

      let
        renderer = newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
        window = newSiwinWindow(size = ivec2(320, 220), title = "figdraw resize test")
      renderer.setupBackend(window)
      check renderer.backendName() == backendName(renderer.backendKind())
      when defined(useNativeDynlib):
        let typedRenderer: SiwinRenderer = renderer
        for enabled in [true, false]:
          let expected = enabled and renderer.backendKind() != rbMetal
          renderer.setTextLcdFiltering(enabled)
          renderer.setTextSubpixelPositioning(enabled)
          renderer.setTextSubpixelGlyphVariants(enabled)
          check renderer.textLcdFiltering() == expected
          check renderer.textSubpixelPositioning() == expected
          check renderer.textSubpixelGlyphVariants() == expected
          check typedRenderer.textLcdFiltering() == expected
          check typedRenderer.textSubpixelPositioning() == expected
          check typedRenderer.textSubpixelGlyphVariants() == expected

      var
        running = true
        resizeCount = 0
        renderCount = 0
        renderedSizes: seq[Vec2]

      proc redraw() =
        let size = window.logicalSize()
        var renders = renderTree(size)
        renderer.beginFrame()
        renderer.renderFrame(renders, size)
        renderer.endFrame()
        renderedSizes.add size
        inc renderCount

      window.eventsHandler = WindowEventsHandler(
        onClose: proc(e: CloseEvent) =
          running = false,
        onResize: proc(e: ResizeEvent) =
          inc resizeCount
          window.redraw(),
        onRender: proc(e: RenderEvent) =
          redraw(),
      )

      try:
        window.firstStep(true)
        window.redraw()
        for _ in 0 ..< 20:
          window.step()
          if renderCount > 0:
            break

        let
          initialRenderCount = renderCount
          requestedSize = window.size + ivec2(80, 60)
        resizeCount = 0
        window.size = requestedSize
        when defined(macosx):
          check resizeCount > 0
        window.redraw()

        for _ in 0 ..< 60:
          window.step()
          if resizeCount > 0 and renderCount > initialRenderCount:
            break

        check running
        check resizeCount > 0
        check renderCount > initialRenderCount
        check renderedSizes.len > 0
        let
          actualSize = window.logicalSize()
          renderedSize = renderedSizes[^1]
        check abs(renderedSize.x - actualSize.x) < 0.01'f32
        check abs(renderedSize.y - actualSize.y) < 0.01'f32
      finally:
        window.eventsHandler = WindowEventsHandler()
        closeWindow(window)
