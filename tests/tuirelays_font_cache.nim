import figdraw/common/fonttypes

when defined(feature.figdraw.uirelays) or figdrawTextBackend == "uirelays":
  ## Portable tests of native-font ownership and layout using a mock relay.
  import std/[os, tables, unicode, unittest]
  import figdraw/common/[fonttypes, typefaces, fontglyphs, shared]
  import figdraw/common/textrasters/uirelays_fonts
  import figdraw/common/textbackends/uirelays as nativeLayout
  from pkg/uirelays/screen as relays import nil

  var
    nextHandle, closes, selectedFace: int
    opened: Table[int, string]

  proc openFace(
      path: string,
      faceIndex, size: int,
      style: relays.FontStyles,
      metrics: var relays.FontMetrics,
  ): relays.Font =
    doAssert fileExists(path)
    selectedFace = faceIndex
    metrics = relays.FontMetrics(
      ascent: size * 3 div 4, descent: size - size * 3 div 4, lineHeight: size
    )
    inc nextHandle
    opened[nextHandle] = path
    relays.Font(nextHandle)

  proc openFont(
      path: string, size: int, style: relays.FontStyles, metrics: var relays.FontMetrics
  ): relays.Font =
    openFace(path, 0, size, style, metrics)

  proc closeFont(font: relays.Font) =
    doAssert font.int in opened
    opened.del(font.int)
    inc closes

  proc measure(font: relays.Font, text: string): relays.TextExtent =
    doAssert font.int in opened
    relays.TextExtent(w: text.runeLen * 10, h: 16)

  proc raster(
      font: relays.Font, text: string, color: relays.Color, pixels: var seq[uint32]
  ): relays.TextExtent =
    result = measure(font, text)
    pixels = newSeq[uint32](result.w * result.h)

  let fonts = relays.FontRelays(
    openFont: openFont,
    openFontFace: openFace,
    closeFont: closeFont,
    measureText: measure,
    renderText: raster,
  )
  let face = loadTypeface("Ubuntu.ttf")
  let font = FigFont(typefaceId: face, size: 16)

  suite "UIRelays font ownership and layout":
    setup:
      initUirelaysFontProvider(fonts, maxFonts = 2)
    teardown:
      clearUirelaysFontCache()
      check opened.len == 0

    test "eviction closes handles and retained tokens reopen safely":
      let first = relayFont(font, 1)
      for size in 17 .. 24:
        discard relayFont(FigFont(typefaceId: face, size: size.float32), 1)
        check cachedRelayFontCount() <= 2
        check opened.len <= 2
      let previous = nextHandle
      check first.relayTextWidth("abc") == 30
      check nextHandle == previous + 1

    test "clearing a font closes handles and removes copied bytes":
      let memoryFace = loadTypeface(
        "memory-font.ttf", readFile(figDataDir() / "HackNerdFont-Regular.ttf"), TTF
      )
      let memoryFont = FigFont(typefaceId: memoryFace, size: 16)
      discard relayFont(memoryFont, 1)
      let path = opened[nextHandle]
      check fileExists(path)
      clearUirelaysFontCache(cacheFont(memoryFont))
      check cachedRelayFontCount() == 0
      check not fileExists(path)
      check closes > 0

    test "native provider preserves the selected collection face":
      let collection = loadTypeface(
        SystemTypefaceFile(
          path: getCurrentDir() / "deps/pixie/tests/fonts/PTSans.ttc", faceIndex: 1
        )
      )
      discard relayFont(FigFont(typefaceId: collection, size: 16), 1)
      check selectedFace == 1
      clearUirelaysTypefaceCache(collection)
      check cachedRelayFontCount() == 0

    test "failed font opening removes its temporary file":
      var rejecting = fonts
      rejecting.openFontFace = proc(
          path: string,
          faceIndex, size: int,
          style: relays.FontStyles,
          metrics: var relays.FontMetrics,
      ): relays.Font =
        opened[-1] = path
        relays.Font(0)
      initUirelaysFontProvider(rejecting)
      let memoryFace = loadTypeface(
        "memory-font.ttf", readFile(figDataDir() / "HackNerdFont-Regular.ttf"), TTF
      )
      expect ValueError:
        discard relayFont(FigFont(typefaceId: memoryFace, size: 16), 1)
      check not fileExists(opened[-1])
      opened.del(-1)

    test "custom line spacing retains the bitmap baseline":
      var spaced = font
      spaced.lineHeight = 40
      let layout = nativeLayout.typeset(
        rect(0, 0, 400, 100),
        [(FontStyle(font: spaced), "A")],
        Left,
        Top,
        false,
        false,
        false,
      )
      let glyph = layout.arrangedGlyphs[0]
      let bitmapTop = glyph.pos.y - layout.fonts[0].descentAdj + glyph.imageOffset.y
      check glyph.pos.y == 24
      check bitmapTop == 12
      check bitmapTop + 12 == glyph.pos.y
      check glyph.rasterBackend == GlyphRasterBackend.Uirelays

    test "mixed fonts share a bitmap baseline with different line spacing":
      let small = FigFont(typefaceId: face, size: 16, lineHeight: 40)
      let large = FigFont(typefaceId: face, size: 32, lineHeight: 64)
      let layout = nativeLayout.typeset(
        rect(0, 0, 400, 100),
        [(FontStyle(font: small), "A"), (FontStyle(font: large), "B")],
        Left,
        Top,
        false,
        false,
        false,
      )
      check layout.positions[0].y == layout.positions[1].y
      check layout.positions[0].y == 40
      for i in 0 .. 1:
        let glyph = layout.arrangedGlyphs[i]
        let bitmapTop = glyph.pos.y - layout.fonts[i].descentAdj
        let ascent = if i == 0: 12'f32 else: 24'f32
        check bitmapTop + ascent == 40
else:
  echo "Skipping UIRelays font cache tests (enable the uirelays feature)"
