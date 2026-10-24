import std/[hashes, math, unittest, unicode]

when defined(features.figdraw.uirelays):
  import pkg/[chroma, pixie]
  import figdraw/[figbackend, fignodes, figrender]
  import figdraw/software/context
  import figdraw/software/windowing
  import figdraw/common/[fontglyphs, fontutils, typefaces]

  proc begin(ctx: SoftwareContext, width = 64, height = 64) =
    ctx.beginFrame(vec2(width.float32, height.float32), true, color(0, 0, 0, 0))

  proc capture(ctx: SoftwareContext): Image =
    ctx.readPixels(rect(0, 0, 0, 0), false)

  suite "software sdfy backend":
    test "elliptical corners use both axes in image corner order":
      let ctx = newSoftwareContext()
      ctx.begin()
      let radii = CornerRadii2D[float32](x: [20'f32, 0, 0, 0], y: [8'f32, 0, 0, 0])
      ctx.drawRoundedRectSdf(
        rect(8, 8, 48, 48), color(1, 0, 0, 1), radii, sdfModeClipAA, 4, 0, vec2(0, 0)
      )
      let image = ctx.capture()
      check image[8, 8].a == 0
      check image[20, 8].a > 0
      check image[8, 17].a == 255
      check image[55, 8].a == 255

    test "scene traversal preserves gradients and glyph-independent transforms":
      let ctx = newSoftwareContext()
      let renderer = newFigRenderer(ctx)
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel,
        Fig(
          kind: nkRectangle,
          screenBox: rect(8, 8, 48, 48),
          fill: linear(rgba(255, 0, 0, 255), rgba(0, 0, 255, 255), fgaX),
        ),
      )
      renderer.renderFrame(nodes, vec2(64, 64), clearColor = color(0, 0, 0, 0))
      let image = ctx.capture()
      check image[10, 30].r > 230
      check image[53, 30].b > 230
      check image[0, 0].a == 0
      check renderer.backendKind() == rbSoftware

    test "nested rounded masks intersect and restore after transformed draws":
      let ctx = newSoftwareContext()
      ctx.begin()
      ctx.beginMask(rect(4, 4, 40, 40), [8'f32, 8, 8, 8])
      ctx.endMask()
      ctx.beginRectMask(rect(20, 0, 40, 64), [0'f32, 0, 0, 0])
      ctx.saveTransform()
      ctx.translate(vec2(10, 0))
      ctx.drawRect(rect(0, 0, 64, 64), color(1, 0, 0, 1))
      ctx.restoreTransform()
      ctx.popRectMask()
      ctx.popMask()
      ctx.drawRect(rect(0, 50, 4, 4), color(0, 1, 0, 1))
      let image = ctx.capture()
      check image[25, 20].r == 255
      check image[15, 20].a == 0
      check image[45, 20].a == 0
      check image[2, 52].g == 255

    test "premultiplied alpha, image tint, flip and capture ownership":
      let ctx = newSoftwareContext()
      ctx.begin()
      ctx.drawRect(rect(0, 0, 64, 64), color(0, 0, 1, 1))
      ctx.drawRect(rect(0, 0, 16, 16), color(1, 0, 0, 0.5))
      let bitmap = newImage(2, 2)
      bitmap[0, 0] = rgba(255, 0, 0, 255)
      bitmap[0, 1] = rgba(0, 255, 0, 255)
      ctx.putImage(123.Hash, bitmap)
      ctx.drawImage(123.Hash, vec2(20, 20), color(1, 1, 1, 1), vec2(2, 2), true)
      let image = ctx.capture()
      check abs(image[4, 4].r.int - 128) <= 1
      check abs(image[4, 4].b.int - 127) <= 1
      check image[20, 20].g == 255
      image[0, 0] = rgba(0, 255, 0, 255)
      check ctx.capture()[0, 0].g == 0

    test "rotation and matrix transforms map framebuffer samples into local space":
      let ctx = newSoftwareContext()
      ctx.begin()
      ctx.saveTransform()
      ctx.translate(vec2(32, 16))
      ctx.rotate(PI.float32 * 0.5'f32)
      ctx.drawRect(rect(0, 0, 8, 12), color(1, 0, 0, 1))
      ctx.restoreTransform()
      ctx.applyTransform(translate(vec3(4, 40, 0)))
      ctx.drawRect(rect(0, 0, 8, 8), color(0, 1, 0, 1))
      let image = ctx.capture()
      check image[26, 20].r == 255
      check image[34, 20].a == 0
      check image[6, 42].g == 255

    test "cache invalidation regenerates a changed image":
      let ctx = newSoftwareContext()
      let renderer = newFigRenderer(ctx)
      let bitmap = newImage(2, 2)
      bitmap.fill(rgba(255, 0, 0, 255))
      check renderer.ensureImage(ImageId(55), bitmap)
      ctx.clearFontGlyphs(FontId(1))
      renderer.clearImage(ImageId(55))
      renderer.processImageMessages()
      check not renderer.containsImage(ImageId(55))
      check renderer.ensureImage(ImageId(55), bitmap)

    test "window image presenter replaces cached frames and preserves dimensions":
      let ctx = newSoftwareContext()
      let host = newFigRenderer(ctx)
      let image = newImage(8, 6)
      image.fill(rgba(10, 20, 30, 255))
      host.presentSoftwareFrame(image)
      check ctx.capture().width == 8
      check ctx.capture().height == 6
      check ctx.capture()[4, 3].r == 10
      image.fill(rgba(30, 40, 50, 255))
      host.presentSoftwareFrame(image)
      check ctx.capture()[4, 3].r == 30
      let resized = newImage(4, 2)
      resized.fill(rgba(60, 70, 80, 255))
      host.presentSoftwareFrame(resized)
      check ctx.capture().width == 4
      check ctx.capture()[1, 1].r == 60

    test "pixel scale, resize and preserved frame contents":
      let ctx = newSoftwareContext(pixelScale = 2)
      ctx.begin(16, 16)
      ctx.scale(2)
      ctx.drawRect(rect(1, 1, 4, 4), color(1, 0, 0, 1))
      check ctx.capture().width == 32
      check ctx.capture()[3, 3].r == 255
      ctx.beginFrame(vec2(16, 16), false, color(0, 0, 0, 0))
      check ctx.capture()[3, 3].r == 255
      ctx.begin(8, 8)
      check ctx.capture().width == 16
      check ctx.capture()[3, 3].a == 0

    test "quadratic strokes handle straight segments and cap styles":
      let ctx = newSoftwareContext()
      let paint = BackendFill(kind: bfColor, color: rgba(255, 255, 255, 255))
      for cap in [scRound, scButt, scSquare]:
        ctx.begin()
        ctx.drawQuadraticBezierSdf(
          rect(0, 0, 64, 32), paint, vec2(-16, 0), vec2(0, 0), vec2(16, 0), 8, cap
        )
        let image = ctx.capture()
        check image[32, 16].a == 255
        check image[32, 24].a == 0
        check (image[13, 16].a > 0) == (cap != scButt)
      ctx.begin()
      ctx.drawQuadraticBezierSdf(
        rect(0, 0, 64, 64), paint, vec2(-24, 16), vec2(0, -32), vec2(24, 16), 6, scRound
      )
      check ctx.capture()[32, 24].a > 240

    test "scene curves retain their bounding-box-local control points":
      let ctx = newSoftwareContext()
      let renderer = newFigRenderer(ctx)
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel,
        Fig(
          kind: nkDrawable,
          screenBox: rect(10, 10, 64, 64),
          drawStroke: RenderStroke(weight: 6, fill: rgba(255, 0, 0, 255), cap: scRound),
          drawOps: @[drawableBezier(@[vec2(8, 48), vec2(32, 0), vec2(56, 48)])],
        ),
      )
      renderer.renderFrame(nodes, vec2(96, 96), clearColor = color(0, 0, 0, 0))
      check ctx.capture()[42, 34].a > 240
      check ctx.capture()[42, 50].a == 0

    test "shadows preserve color alpha and fade outside elliptical shapes":
      let ctx = newSoftwareContext()
      ctx.begin()
      ctx.drawRoundedRectSdf(
        rect(0, 0, 64, 64),
        color(1, 0, 0, 0.5),
        [4'f32, 4, 4, 4],
        sdfModeDropShadow,
        8,
        0,
        vec2(24, 24),
      )
      let image = ctx.capture()
      check abs(image[32, 32].a.int - 128) <= 1
      check image[45, 32].a > image[52, 32].a
      check image[52, 32].a > image[59, 32].a

    test "backdrop blur replaces translucent pixels without doubling alpha":
      let ctx = newSoftwareContext()
      ctx.begin()
      ctx.drawRect(rect(0, 0, 32, 64), color(1, 0, 0, 0.5))
      ctx.drawRect(rect(32, 0, 32, 64), color(0, 0, 1, 0.5))
      ctx.drawBackdropBlur(rect(16, 16, 32, 32), [0'f32, 0, 0, 0], 4)
      let image = ctx.capture()
      check image[31, 32].r > 0
      check image[31, 32].b > 0
      check abs(image[31, 32].a.int - 128) <= 2
      check image[31, 8].b == 0

    test "distance images use median RGB or true-distance alpha":
      let ctx = newSoftwareContext()
      ctx.begin()
      let bitmap = newImage(4, 4)
      bitmap.fill(rgba(0, 0, 0, 255))
      ctx.putImage(456.Hash, bitmap)
      ctx.drawMsdfImage(
        456.Hash, vec2(0, 0), color(1, 0, 0, 1), vec2(16, 16), 4, 0.5, 0, false
      )
      ctx.drawMtsdfImage(
        456.Hash, vec2(24, 0), color(0, 1, 0, 1), vec2(16, 16), 4, 0.5, 0, false
      )
      check ctx.capture()[8, 8].a == 0
      check ctx.capture()[32, 8].g == 255
      bitmap.fill(rgba(255, 255, 255, 255))
      ctx.updateImage(456.Hash, bitmap)
      ctx.drawMsdfImage(
        456.Hash, vec2(0, 24), color(1, 0, 0, 1), vec2(16, 16), 4, 0.5, 0, false
      )
      check ctx.capture()[8, 32].r == 255

    test "normal glyph layouts render and font invalidation discards glyph images":
      let
        face = loadTypeface("data/Ubuntu.ttf")
        font = FigFont(typefaceId: face, size: 18)
        layout = placeGlyphs(font, [(Rune(65), vec2(8, 8))], origin = GlyphTopLeft)
        ctx = newSoftwareContext()
        renderer = newFigRenderer(ctx)
      var nodes = newRenders()
      discard nodes.addRoot(
        0.ZLevel, Fig(kind: nkText, screenBox: rect(0, 0, 64, 64), textLayout: layout)
      )
      renderer.renderFrame(nodes, vec2(64, 64), clearColor = color(0, 0, 0, 0))
      var painted = 0
      for pixel in ctx.capture().data:
        if pixel.a > 0:
          inc painted
      check painted > 20
      for glyph in layout.glyphs():
        check ctx.hasImage(glyph.hash())
        ctx.clearFontGlyphs(glyph.fontId)
        check not ctx.hasImage(glyph.hash())
      renderer.renderFrame(nodes, vec2(64, 64), clearColor = color(0, 0, 0, 0))
      for glyph in layout.glyphs():
        check ctx.hasImage(glyph.hash())

    test "invalid scale and unbalanced stacks raise clear errors":
      expect ValueError:
        discard newSoftwareContext(pixelScale = 0)
      let ctx = newSoftwareContext()
      ctx.begin()
      expect ValueError:
        ctx.popMask()
      expect ValueError:
        ctx.restoreTransform()
else:
  suite "software backend (optional uirelays feature)":
    test "requires Atlas uirelays feature":
      skip()
