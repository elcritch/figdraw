import std/unittest

import figdraw
import figdraw/windowing/siwinshim

when defined(macosx) and (UseMetalBackend or UseVulkanBackend):
  import darwin/app_kit/nsview
  import darwin/core_graphics/cggeometry
  import darwin/foundation/nsstring
  import darwin/objc/runtime
  import darwin/quartz_core/calayer

  proc layerContentsPlacement(
    view: NSView
  ): NSInteger {.objc: "layerContentsPlacement".}

  proc backgroundColor(layer: CALayer): pointer {.objc: "backgroundColor".}
  proc contentsGravity(layer: CALayer): NSString {.objc: "contentsGravity".}
  proc colorComponentCount(
    color: pointer
  ): csize_t {.importc: "CGColorGetNumberOfComponents".}

  proc colorComponents(
    color: pointer
  ): ptr UncheckedArray[CGFloat] {.importc: "CGColorGetComponents".}

  const LayerContentsPlacementTopLeft = 11.NSInteger
  var kCAGravityTopLeft {.importc.}: NSString

  proc checkLayerPolicy(renderer: FigRenderer[SiwinRenderBackend], window: Window) =
    let handle =
      when UseMetalBackend:
        renderer.backendState.metalLayer
      else:
        renderer.backendState.vulkanMetalLayer
    let layer = cast[CALayer](handle.layer)

    check handle.hostView.layerContentsPlacement() == LayerContentsPlacementTopLeft
    check layer.contentsGravity() == kCAGravityTopLeft

    var renders = newRenders()
    let expected = color(0.16'f32, 0.31'f32, 0.47'f32, 1.0'f32)
    renderer.beginFrame()
    renderer.renderFrame(renders, window.logicalSize(), clearColor = expected)
    renderer.endFrame()

    let background = layer.backgroundColor()
    check not background.isNil
    check background.colorComponentCount() == 4
    let components = background.colorComponents()
    check abs(components[0].float32 - expected.r) < 0.001'f32
    check abs(components[1].float32 - expected.g) < 0.001'f32
    check abs(components[2].float32 - expected.b) < 0.001'f32
    check abs(components[3].float32 - expected.a) < 0.001'f32

suite "siwin resize presentation":
  test "keeps the last Metal frame unscaled and fills exposed space":
    when defined(macosx) and (UseMetalBackend or UseVulkanBackend):
      let
        renderer = newFigRenderer(atlasSize = 192, backendState = SiwinRenderBackend())
        window = newSiwinWindow(
          size = ivec2(320, 220), title = "figdraw resize presentation test"
        )
      try:
        renderer.setupBackend(window)
        renderer.checkLayerPolicy(window)
      finally:
        if window.opened:
          window.close()
    else:
      skip()
