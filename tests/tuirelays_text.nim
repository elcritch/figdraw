import std/[os, unicode, unittest]

import figdraw/common/fonttypes

when figdrawTextBackend != "uirelays":
  echo "Skipping uirelays text backend test (build with -d:figdrawTextBackend=uirelays)"
else:
  import pkg/vmath

  import figdraw/common/fontutils
  import figdraw/common/imgutils
  import figdraw/common/textrasters/uirelays_raster

  let fontPath = getEnv("WINDIR", r"C:\Windows") / "Fonts" / "segoeui.ttf"

  suite "uirelays text backend":
    let font = FigFont(typefaceId: loadTypeface(fontPath), size: 16)

    test "places runes left to right on a shared baseline":
      let text = typesetForMeasurement(
        rect(0, 0, 400, 100),
        [(fs(font), "Hello, world")],
        minContent = false,
        wrap = false,
      )
      check text.lines == @[0 .. 11]
      check text.positions.len == 12
      for i in 1 ..< text.positions.len:
        check text.positions[i].x > text.positions[i - 1].x
        check text.positions[i].y == text.positions[0].y
        check text.selectionRects[i].x ==
          text.selectionRects[i - 1].x + text.selectionRects[i - 1].w

    test "advances are the platform's measured widths":
      let relay = relayFont(font, 1.0)
      let text = typesetForMeasurement(
        rect(0, 0, 400, 100), [(fs(font), "Wave")], minContent = false, wrap = false
      )
      let last = text.selectionRects[^1]
      check last.x + last.w == relay.relayTextWidth("Wave").float32

    test "wraps words within the box and breaks lines at newlines":
      let text = typesetForMeasurement(
        rect(0, 0, 80, 200),
        [(fs(font), "one two three four\nfive")],
        minContent = false,
        wrap = true,
      )
      check text.lines.len >= 3
      check text.runes[text.lines[^1].a] == Rune('f')
      for line in text.lines:
        let first = text.selectionRects[line.a]
        check first.x == 0
        for i in line:
          if not text.runes[i].isWhiteSpace:
            check text.selectionRects[i].x + text.selectionRects[i].w <= 80
      for li in 1 ..< text.lines.len:
        check text.positions[text.lines[li].a].y > text.positions[text.lines[li - 1].a].y

    test "renders glyphs as white coverage on transparency":
      let image =
        renderUirelaysGlyph(ImageId(1), cacheFont(font), Rune('W'), upload = false)
      check not image.isNil
      check image.width > 0 and image.height > 0
      var inked, clear = 0
      for pixel in image.data:
        check pixel.r == pixel.a
        if pixel.a > 0:
          inc inked
        else:
          inc clear
      check inked > 0
      check clear > 0

    test "line spacing keeps the native bitmap baseline":
      var spaced = font
      spaced.lineHeight = 40
      let native = relayFont(spaced, 1)
      let text = typesetForMeasurement(
        rect(0, 0, 400, 100), [(fs(spaced), "A")], minContent = false, wrap = false
      )
      check text.fonts[0].descentAdj == native.metrics.ascent.float32
      check text.positions[0].y > text.fonts[0].descentAdj

    test "collection faces render with their own native widths":
      let path = getCurrentDir() / "deps/pixie/tests/fonts/PTSans.ttc"
      let regular = FigFont(
        typefaceId: loadTypeface(SystemTypefaceFile(path: path, faceIndex: 0)), size: 24
      )
      let bold = FigFont(
        typefaceId: loadTypeface(SystemTypefaceFile(path: path, faceIndex: 1)), size: 24
      )
      check relayFont(regular, 1).relayTextWidth("Hello, world") !=
        relayFont(bold, 1).relayTextWidth("Hello, world")
