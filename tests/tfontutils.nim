import std/[os, unittest, tables, locks, unicode]

import pkg/pixie
import pkg/pixie/fonts

import figdraw/commons
import figdraw/common/fonttypes

proc resetFontState() =
  typefaceTable = initTable[TypefaceId, Typeface]()
  fontTable = initTable[FontId, pixie.Font]()
  #withLock imageCachedLock:
  #  imageCached.clear()

suite "fontutils":
  setup:
    resetFontState()
    setFigDataDir(getCurrentDir() / "data")

  test "load typeface from buffer":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let id1 = getTypefaceImpl("Ubuntu.ttf", fontData, TTF)
    let id2 = getTypefaceImpl("Ubuntu.ttf", fontData, TTF)

    check id1.int != 0
    check id1 == id2
    check id1 in typefaceTable

  test "convertFont caches pixie font":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = getTypefaceImpl("Ubuntu.ttf", fontData, TTF)
    let uiFont = UiFont(typefaceId: typefaceId, size: 20.0'f32,
        lineHeightScale: 0.75)

    let (fontId1, pf1) = uiFont.convertFont()
    let (fontId2, pf2) = uiFont.convertFont()

    check fontId1 == fontId2
    check pf1 == pf2
    check fontId1 in fontTable

  test "lineHeightScale affects computed lineHeight":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = getTypefaceImpl("Ubuntu.ttf", fontData, TTF)
    let uiFont = UiFont(typefaceId: typefaceId, size: 32.0'f32,
        lineHeightScale: 0.5)

    let (_, pf) = uiFont.convertFont()
    let expected = 0.5'f32 * pf.defaultLineHeight()

    check abs(pf.lineHeight - expected) < 0.01'f32
    check abs(getLineHeightImpl(uiFont).scaled() - expected) < 0.01'f32

  test "getTypesetImpl returns consistent hashes and generated glyph images":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = getTypefaceImpl("Ubuntu.ttf", fontData, TTF)
    let uiFont = UiFont(typefaceId: typefaceId, size: 18.0'f32)
    let box = rect(0, 0, 240, 60)
    let spans = [(uiFont, "Hello world")]

    let arrangement = typeset(
      box,
      spans,
      hAlign = Left,
      vAlign = Top,
      minContent = false,
      wrap = false,
    )

    check arrangement.contentHash == getContentHash(box.wh, spans, Left, Top)
    check arrangement.spans.len == spans.len
    check arrangement.fonts.len == spans.len
    check arrangement.runes.len == arrangement.positions.len
    check arrangement.runes.len == arrangement.selectionRects.len
    check arrangement.maxSize.x >= arrangement.minSize.x
    check arrangement.maxSize.y >= arrangement.minSize.y
    check arrangement.bounding.w > 0'f32
    check arrangement.bounding.h > 0'f32

    var foundNonWhitespace = false
    for glyph in arrangement.glyphs():
      if not glyph.rune.isWhiteSpace:
        foundNonWhitespace = true
        check hasImage(glyph.hash().ImageId)
        break
    check foundNonWhitespace

  test "placeGlyphs respects positions and caches glyphs":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = getTypefaceImpl("Ubuntu.ttf", fontData, TTF)
    let uiFont = UiFont(typefaceId: typefaceId, size: 18.0'f32)
    app.uiScale = 1.0

    let a = "A".runeAt(0)
    let b = "B".runeAt(0)
    let positions = [
      (a, vec2(12, 16)),
      (b, vec2(40, 16)),
    ]

    let arrangement = placeGlyphs(uiFont, positions, origin = GlyphTopLeft)

    check arrangement.runes.len == positions.len
    check arrangement.spans.len == 1
    check arrangement.fonts.len == 1

    var idx = 0
    for glyph in arrangement.glyphs():
      let expected = positions[idx][1]
      let charPos = vec2(glyph.pos.x, glyph.pos.y - glyph.descent)
      check abs(charPos.x - expected.x) < 0.01'f32
      check abs(charPos.y - expected.y) < 0.01'f32
      if not glyph.rune.isWhiteSpace:
        check hasImage(glyph.hash().ImageId)
      inc idx
    check idx == positions.len
