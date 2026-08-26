import std/unittest

when defined(useNativeDynlib):
  import figdraw/dynlib

suite "native dynlib API":
  when defined(useNativeDynlib):
    test "supports elliptical corners and drawable ellipses":
      let
        horizontal = [4'u16, 6'u16, 8'u16, 10'u16]
        vertical = [2'u16, 3'u16, 4'u16, 5'u16]
        radii = initCornerRadii2D(horizontal, vertical)
        ellipse = drawableEllipse(vec2(12.0'f32, 18.0'f32), vec2(24.0'f32, 10.0'f32))

      check not radii.isCircular()
      check initCornerRadii2D(horizontal).isCircular()
      check ellipse.kind == dkEllipse
      check ellipse.ellipseCenter.toVec2() == vec2(12.0'f32, 18.0'f32)
      check ellipse.ellipseRadii.toVec2() == vec2(24.0'f32, 10.0'f32)

      var node = Fig(kind: nkRectangle)
      node.corners = horizontal
      node.cornerRadiiY = vertical
      node.flags.incl NfEllipticalCorners
      check NfEllipticalCorners in node.flags

    test "provides source-compatible image and backdrop values":
      var imageRef: ImageRef
      imageRef = nil
      check imageRef == default(ImageRef)

      let
        region = WindowVisualRegion(pos: ivec2(8, 12), size: ivec2(160, 90))
        blur = initWindowBackdrop([region])
        material = initWindowBackdrop(wbmSidebar, [region])
      check blur.kind == wbkBlur
      check blur.regions == @[region]
      check material.kind == wbkMaterial
      check material.material == wbmSidebar

    test "exposes the NimKit Siwin window surface":
      doAssert compiles(
        block:
          var window: Window
          discard window.nativeWindowKey()
          discard window.title()
          window.minSize = ivec2(100, 80)
          window.maxSize = ivec2(1920, 1080)
          window.customTitlebar = true
          window.setTitleRegion(vec2(0, 0), vec2(200, 40))
          window.setInputRegion(vec2(0, 0), vec2(200, 120))
          window.setBorderWidth(6, 8, 12)
          window.startInteractiveMove(vec2(20, 20))
          window.startInteractiveResize(topLeft, vec2(20, 20))
          window.showWindowMenu(vec2(20, 20))
          window.cursor = arrow
          window.vsync = true
          window.separateTouch = true
          window.canBecomeKeyWindow = true
          window.canBecomeMainWindow = true
          discard window.visualCapabilities()
          discard window.trySetBackdrop(WindowBackdropConfig(kind: wbkNone))
      )
  else:
    test "requires useNativeDynlib":
      skip()
