import std/unittest

when defined(features.figdraw.siwin):
  import pkg/[chroma, pixie, vmath]
  import pkg/siwin/window as siWindow
  from pkg/siwin/colorutils import PixelBuffer, PixelBufferFormat
  import figdraw
  import figdraw/software/siwin

  type FakeSoftwareWindow = ref object of siWindow.Window
    pixels: seq[ColorRGBX]
    dimensions: IVec2
    density: float32

  method pixelBuffer(window: FakeSoftwareWindow): PixelBuffer =
    PixelBuffer(
      data: window.pixels[0].addr,
      size: window.dimensions,
      format: PixelBufferFormat.rgbx_32bit,
    )

  method uiScale(window: FakeSoftwareWindow): float32 =
    window.density

  suite "Siwin software presentation":
    test "all buffer formats preserve channels alpha and guarded bounds":
      let image = newImage(2, 1)
      image[0, 0] = rgba(200, 80, 40, 128).rgbx()
      image[1, 0] = rgbx(0, 0, 0, 0)
      let original = image.copy()
      for format in PixelBufferFormat:
        var guarded: array[10, uint8]
        guarded[0] = 0xa5
        guarded[9] = 0x5a
        writeSiwinPixelBuffer(
          image,
          PixelBuffer(data: guarded[1].addr, size: ivec2(2, 1), format: format),
          background = rgba(20, 40, 60, 255),
        )
        let expected: array[8, uint8] =
          case format
          of PixelBufferFormat.rgbx_32bit:
            [100'u8, 40, 20, 128, 0, 0, 0, 0]
          of PixelBufferFormat.bgrx_32bit:
            [20'u8, 40, 100, 128, 0, 0, 0, 0]
          of PixelBufferFormat.xrgb_32bit:
            [128'u8, 100, 40, 20, 0, 0, 0, 0]
          of PixelBufferFormat.rgba_32bit:
            [199'u8, 80, 40, 128, 0, 0, 0, 0]
          of PixelBufferFormat.bgra_32bit:
            [40'u8, 80, 199, 128, 0, 0, 0, 0]
          of PixelBufferFormat.bgru_32bit:
            [49'u8, 59, 109, 255, 60, 40, 20, 255]
          of PixelBufferFormat.urgb_32bit:
            [255'u8, 109, 59, 49, 255, 20, 40, 60]
          of PixelBufferFormat.rgbu_32bit:
            [109'u8, 59, 49, 255, 20, 40, 60, 255]
        check guarded[0] == 0xa5
        check guarded[9] == 0x5a
        for i in 0 ..< expected.len:
          check guarded[i + 1] == expected[i]
        check image.data == original.data

    test "fractional scale resize and presentation keep exact backing dimensions":
      let previousScale = figUiScale()
      defer:
        setFigUiScale(previousScale)
      let window = FakeSoftwareWindow(density: 1)
      let renderer = newSiwinSoftwareRenderer(
        window, background = rgba(0, 0, 255, 255), parallelThreshold = 1
      )
      for density in [1'f32, 1.25, 1.5, 1.75, 2]:
        window.density = density
        for dimensions in [ivec2(67, 61), ivec2(131, 97)]:
          window.dimensions = dimensions
          window.pixels.setLen(dimensions.x * dimensions.y)
          let size = configureSiwinSoftwareScale(window)
          var nodes = newRenders()
          discard nodes.addRoot(
            0.ZLevel,
            Fig(
              kind: nkRectangle,
              screenBox: rect(0, 0, size.x, size.y),
              corners: [3'u16, 3, 3, 3],
              cornerRadiiY: [2'u16, 2, 2, 2],
              flags: {NfEllipticalCorners},
              fill: rgba(255, 0, 0, 128),
            ),
          )
          renderer.renderFrame(nodes, size, clearColor = color(0, 0, 0, 0))
          let frame = renderer.ctx.readPixels(rect(0, 0, 0, 0), false)
          check frame.width == dimensions.x
          check frame.height == dimensions.y
          check frame[5, 5].a == 128
          check window.pixels[5 * dimensions.x + 5] == rgbx(128, 0, 127, 255)
          check renderer.backendKind() == rbSoftware

    test "invalid buffers fail before writing":
      let image = newImage(2, 1)
      var pixels: array[2, ColorRGBX]
      expect ValueError:
        writeSiwinPixelBuffer(
          image,
          PixelBuffer(
            data: pixels[0].addr,
            size: ivec2(1, 1),
            format: PixelBufferFormat.rgbx_32bit,
          ),
        )
      check pixels == default(array[2, ColorRGBX])
      expect ValueError:
        writeSiwinPixelBuffer(image, PixelBuffer(data: nil, size: ivec2(2, 1)))
      expect ValueError:
        discard newSiwinSoftwareContext(nil)
else:
  suite "Siwin software presentation":
    test "requires Atlas siwin feature":
      skip()
