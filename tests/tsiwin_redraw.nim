import std/unittest
when defined(linux) or defined(bsd):
  import std/os

when defined(useNativeDynlib):
  import figdraw/dynlib
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
        window.firstStep()
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
        closeWindow(window)
