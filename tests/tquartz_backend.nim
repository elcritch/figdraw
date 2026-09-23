import std/unittest

import figdraw/commons

when UseQuartzBackend:
  import pkg/[chroma, pixie]
  import figdraw/figrender
  import figdraw/fignodes

  proc renderFixture(): Image =
    let width = 180'f32
    let height = 130'f32
    var renders = newRenders()
    let root = renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkRectangle,
        screenBox: rect(0, 0, width, height),
        fill: rgba(250, 250, 250, 255),
      ),
    )
    discard renders.addChild(
      0.ZLevel,
      root,
      Fig(
        kind: nkRectangle,
        screenBox: rect(12, 12, 70, 46),
        corners: [12'u16, 12'u16, 12'u16, 12'u16],
        cornerRadiiY: [6'u16, 16'u16, 8'u16, 18'u16],
        flags: {NfEllipticalCorners},
        fill: rgba(220, 40, 50, 255),
      ),
    )
    discard renders.addChild(
      0.ZLevel,
      root,
      Fig(
        kind: nkDrawable,
        screenBox: rect(96, 12, 70, 46),
        fill: fill(rgba(30, 120, 220, 255)),
        drawStroke: RenderStroke(weight: 2, fill: rgba(10, 30, 70, 255)),
        drawOps: @[drawableEllipse(vec2(35, 23), vec2(30, 18))],
      ),
    )
    discard renders.addChild(
      0.ZLevel,
      root,
      Fig(
        kind: nkRectangle,
        screenBox: rect(100, 72, 32, 32),
        corners: [16'u16, 16'u16, 16'u16, 16'u16],
        fill: rgba(40, 170, 95, 255),
      ),
    )
    let imageId = ImageId(91)
    let bitmap = newImage(8, 8)
    for y in 0 ..< bitmap.height:
      let rowColor =
        if y < bitmap.height div 2:
          rgba(245, 190, 30, 255)
        else:
          rgba(40, 90, 210, 255)
      for x in 0 ..< bitmap.width:
        bitmap[x, y] = rowColor
    let imageRenderer = newFigRenderer(atlasSize = 32)
    doAssert imageRenderer.ensureImage(imageId, bitmap)
    discard renders.addChild(
      0.ZLevel,
      root,
      Fig(kind: nkImage, screenBox: rect(142, 74, 24, 24), image: imageStyle(imageId)),
    )
    discard renders.addChild(
      0.ZLevel,
      root,
      Fig(
        kind: nkDrawable,
        screenBox: rect(12, 76, 154, 42),
        fill: fill(rgba(0, 0, 0, 0)),
        drawStroke: RenderStroke(weight: 4, fill: rgba(25, 40, 65, 255), cap: scRound),
        drawOps:
          @[
            drawableLine(vec2(4, 32), vec2(48, 8)),
            drawableBezier(@[vec2(58, 32), vec2(90, 0), vec2(142, 28)]),
          ],
      ),
    )

    let renderer = imageRenderer
    renderer.renderFrame(
      renders, vec2(width, height), clearColor = rgba(250, 250, 250, 255).color
    )
    result = renderer.takeOneFrameScreenshot()

  proc near(a, b: uint8, tolerance = 4): bool =
    abs(a.int - b.int) <= tolerance

  proc nearColor(pixel: ColorRGBX, expected: ColorRGBA, tolerance = 4): bool =
    near(pixel.r, expected.r, tolerance) and near(pixel.g, expected.g, tolerance) and
      near(pixel.b, expected.b, tolerance)

suite "Quartz 2D backend":
  test "renders an offscreen fixture with paths":
    when UseQuartzBackend:
      let image = renderFixture()
      check image.width == 180
      check image.height == 130
      check nearColor(image[40, 30], rgba(220, 40, 50, 255))
      check nearColor(image[12, 12], rgba(250, 250, 250, 255))
      check nearColor(image[131, 35], rgba(30, 120, 220, 255))
      check nearColor(image[116, 88], rgba(40, 170, 95, 255))
      check nearColor(image[154, 77], rgba(245, 190, 30, 255))
      check nearColor(image[154, 94], rgba(40, 90, 210, 255))
      check image[22, 105].r < 100
    else:
      skip()
