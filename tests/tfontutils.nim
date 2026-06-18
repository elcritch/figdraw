import std/[os, unittest, tables, locks, unicode]

import pkg/pixie
import pkg/pixie/fonts

import figdraw/commons
import figdraw/common/fonttypes
import figdraw/common/typefaces
import figdraw/common/fontglyphs
import figdraw/extras/systemfonts

proc resetFontState() =
  typefaceTable = initTable[TypefaceId, Typeface]()
  fontTable = initTable[FontId, FigFont]()
  typefaceSourceTable = initTable[TypefaceId, TypefaceSource]()
  staticTypefaceTable =
    initTable[string, tuple[name: string, data: string, kind: TypeFaceKinds]]()
  #withLock imageCachedLock:
  #  imageCached.clear()

suite "fontutils":
  setup:
    resetFontState()
    setFigDataDir(getCurrentDir() / "data")

  test "load typeface from buffer":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let id1 = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let id2 = loadTypeface("Ubuntu.ttf", fontData, TTF)

    check id1.int != 0
    check id1 == id2
    check id1 in typefaceTable
    check id1 in typefaceSourceTable
    check typefaceSourceTable[id1].data == fontData

  test "convertFont caches pixie font":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 20.0'f32)

    let (fontId1, pf1) = uiFont.convertFont()
    let (fontId2, pf2) = uiFont.convertFont()

    check fontId1 == fontId2
    check fontId1 in fontTable

  test "lineHeight affects computed lineHeight":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)

    let (_, pf) = uiFont.convertFont()
    let expected = pf.defaultLineHeight()

    check abs(pf.lineHeight - expected) < 0.01'f32
    check abs(getLineHeightImpl(uiFont).scaled() - expected) < 0.01'f32

  test "getTypesetImpl returns consistent hashes and generated glyph images":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let box = rect(0, 0, 240, 60)
    let spans = [(fs(uiFont), "Hello world")]

    let arrangement =
      typeset(box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false)

    let expectedHash = block:
      var h = Hash(0)
      h = h !& getContentHash(box.wh, spans, Left, Top)
      h = h !& hash(figUiScale())
      !$h
    check arrangement.contentHash == expectedHash
    check arrangement.spans.len == spans.len
    check arrangement.fonts.len == spans.len
    check arrangement.spanColors.len == spans.len
    check arrangement.runes.len == arrangement.positions.len
    check arrangement.runes.len == arrangement.selectionRects.len
    check arrangement.sourceRunes == arrangement.runes
    check arrangement.arrangedGlyphs.len == arrangement.runes.len
    check arrangement.maxSize.x >= arrangement.minSize.x
    check arrangement.maxSize.y >= arrangement.minSize.y
    check arrangement.bounding.w > 0'f32
    check arrangement.bounding.h > 0'f32

    for i in 0 ..< arrangement.arrangedGlyphs.len:
      let arranged = arrangement.arrangedGlyphs[i]
      check arranged.rune == arrangement.runes[i]
      check arranged.pos == arrangement.positions[i]
      check arranged.rect == arrangement.selectionRects[i]
      when figdrawTextBackend == "pixie":
        check arranged.glyphId == syntheticFontGlyphId(arranged.fontId, arranged.rune)
      else:
        check arranged.glyphId != FontGlyphId(0)
      check arrangement.sourceRune(i) == arrangement.runes[i]
      check arrangement.sourceRuneRange(i) == i .. i

      var sourceCount = 0
      for sourceRune in sourceRunes(arrangement, i):
        check sourceRune == arrangement.runes[i]
        inc sourceCount
      check sourceCount == 1

    var foundNonWhitespace = false
    for glyph in arrangement.glyphs():
      if not glyph.rune.isWhiteSpace:
        foundNonWhitespace = true
        when figdrawTextBackend == "pixie":
          check glyph.glyphId == syntheticFontGlyphId(glyph.fontId, glyph.rune)
        else:
          check glyph.glyphId != FontGlyphId(0)
        check glyph.source.runeStart >= 0
        check glyph.source.runeEnd == glyph.source.runeStart + 1
        when figdrawTextBackend != "harfbuzzy":
          check hasImage(glyph.hash().ImageId)
        break
    check foundNonWhitespace

  when figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid":
    test "harfbuzzy backend emits shaped glyph ids and source ranges":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
      let box = rect(0, 0, 240, 60)
      let spans = [(fs(uiFont), "Hello")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.sourceRunes.len == 5
      check arrangement.arrangedGlyphs.len == 5

      var foundShapedId = false
      for i, glyph in arrangement.arrangedGlyphs:
        check glyph.source.runeStart == i
        check glyph.source.runeEnd == i + 1
        if glyph.glyphId != syntheticFontGlyphId(glyph.fontId, glyph.rune):
          foundShapedId = true
      check foundShapedId

    test "source range helpers map ligatures back to source runes":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
      let box = rect(0, 0, 300, 80)
      let spans = [(fs(uiFont), "office")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.sourceRunes.len == 6
      check arrangement.arrangedGlyphs.len < arrangement.sourceRunes.len

      let ligatureGlyphRange = arrangement.glyphRangeForSourceRunes(1 .. 3)
      check ligatureGlyphRange.a == ligatureGlyphRange.b

      let ligatureGlyph = ligatureGlyphRange.a
      check arrangement.sourceRuneRange(ligatureGlyph) == 1 .. 3

      var source = ""
      for rune in sourceRunes(arrangement, ligatureGlyph):
        source.add $rune
      check source == "ffi"

      let rects = arrangement.selectionRectsForSourceRunes(2 .. 2)
      check rects.len == 1
      check rects[0] == arrangement.arrangedGlyphs[ligatureGlyph].rect

      let hitPoint = vec2(rects[0].x + rects[0].w / 2, rects[0].y + rects[0].h / 2)
      check arrangement.glyphIndexAt(hitPoint) == ligatureGlyph
      check arrangement.sourceRuneRangeAt(hitPoint) == 1 .. 3

  when figdrawTextBackend == "harfbuzzy":
    test "harfbuzzy glyph id raster provider renders shaped glyph images":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
      let box = rect(0, 0, 300, 80)
      let spans = [(fs(uiFont), "office")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )
      let glyphIndex = arrangement.glyphRangeForSourceRunes(1 .. 3).a

      var glyphs = newSeq[GlyphPosition]()
      for glyph in arrangement.glyphs():
        glyphs.add glyph

      check glyphIndex >= 0
      check glyphIndex < glyphs.len
      let image = glyphs[glyphIndex].generateGlyph(force = true, upload = false)

      check image != nil
      check image.width > 0
      check image.height > 0
      check image.opaqueBounds().w > 0
      check image.opaqueBounds().h > 0

  test "glyph hash separates lcd filtering variants":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let box = rect(0, 0, 240, 60)
    let spans = [(fs(uiFont), "A")]
    let arrangement =
      typeset(box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false)

    var checked = false
    for glyph in arrangement.glyphs():
      if glyph.rune.isWhiteSpace:
        continue
      check glyph.hash(lcdFiltering = false) != glyph.hash(lcdFiltering = true)
      checked = true
      break
    check checked

  test "glyph hash separates glyph-variant subpixel steps":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let box = rect(0, 0, 240, 60)
    let spans = [(fs(uiFont), "A")]
    let arrangement =
      typeset(box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false)

    var checked = false
    for glyph in arrangement.glyphs():
      if glyph.rune.isWhiteSpace:
        continue
      check glyph.hash(subpixelVariant = 0) != glyph.hash(subpixelVariant = 1)
      checked = true
      break
    check checked

  test "glyph hash uses glyph id for cache identity":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let box = rect(0, 0, 240, 60)
    let spans = [(fs(uiFont), "A")]
    let arrangement =
      typeset(box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false)

    let b = "B".runeAt(0)
    var checked = false
    for glyph in arrangement.glyphs():
      if glyph.rune.isWhiteSpace:
        continue
      let sameGlyphDifferentRune =
        GlyphPosition(fontId: glyph.fontId, glyphId: glyph.glyphId, rune: b)
      let differentGlyphSameRune = GlyphPosition(
        fontId: glyph.fontId,
        glyphId: syntheticFontGlyphId(glyph.fontId, b),
        rune: glyph.rune,
      )

      check glyph.hash() == sameGlyphDifferentRune.hash()
      check glyph.hash() != differentGlyphSameRune.hash()
      checked = true
      break
    check checked

  test "glyph-variant subpixel step maps fractional x to 10 steps":
    check toGlyphVariantSubpixelStep(0.0'f32) == 0
    check toGlyphVariantSubpixelStep(0.09'f32) == 0
    check toGlyphVariantSubpixelStep(0.10'f32) == 1
    check toGlyphVariantSubpixelStep(0.59'f32) == 5
    check toGlyphVariantSubpixelStep(0.999'f32) == 9
    check toGlyphVariantSubpixelStep(1.25'f32) == 9

  test "lcd filter applies freetype 5-tap kernel":
    var image = newImage(7, 1)
    image[3, 0] = rgba(255, 255, 255, 255)
    image.applyLcdFilter()

    let expected = [0'u8, 8'u8, 77'u8, 86'u8, 77'u8, 8'u8, 0'u8]
    for x in 0 ..< expected.len:
      let px = image[x, 0]
      check px.r == expected[x]
      check px.g == expected[x]
      check px.b == expected[x]
      check px.a == expected[x]

  test "typeset preserves gradient span fills":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let box = rect(0, 0, 240, 60)
    let spans = [
      (
        fs(uiFont, linear(rgba(220, 40, 40, 255), rgba(40, 90, 220, 255), axis = fgaX)),
        "Gradient text",
      )
    ]

    let arrangement =
      typeset(box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false)

    check arrangement.spanColors.len == 1
    check arrangement.spanColors[0].kind == flLinear2
    check arrangement.spanColors[0].lin2.axis == fgaX
    check arrangement.spanColors[0].lin2.start == rgba(220, 40, 40, 255)
    check arrangement.spanColors[0].lin2.stop == rgba(40, 90, 220, 255)

  test "placeGlyphs respects positions and caches glyphs":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    setFigUiScale 1.0

    let a = "A".runeAt(0)
    let b = "B".runeAt(0)
    let positions = [(a, vec2(12, 16)), (b, vec2(40, 16))]

    let arrangement = placeGlyphs(uiFont, positions, origin = GlyphTopLeft)

    check arrangement.runes.len == positions.len
    check arrangement.sourceRunes == arrangement.runes
    check arrangement.arrangedGlyphs.len == positions.len
    check arrangement.spans.len == 1
    check arrangement.fonts.len == 1

    var idx = 0
    for glyph in arrangement.glyphs():
      let expected = positions[idx][1]
      let charPos = vec2(glyph.pos.x, glyph.pos.y - glyph.descent)
      check abs(charPos.x - expected.x) < 0.01'f32
      check abs(charPos.y - expected.y) < 0.01'f32
      check glyph.glyphId == syntheticFontGlyphId(glyph.fontId, glyph.rune)
      check arrangement.sourceRune(idx) == positions[idx][0]
      check arrangement.sourceRuneRange(idx) == idx .. idx
      if not glyph.rune.isWhiteSpace:
        check hasImage(glyph.hash().ImageId)
      inc idx
    check idx == positions.len

  test "loadTypeface prefers figDataDir over other paths":
    let oldDataDir = figDataDir()
    let tempDir = getTempDir() / "figdraw-font-priority-test"
    let fontName = "Ubuntu.ttf"
    let tempFontPath = tempDir / fontName
    if not dirExists(tempDir):
      createDir(tempDir)

    copyFile(oldDataDir / fontName, tempFontPath)
    setFigDataDir(tempDir)
    defer:
      setFigDataDir(oldDataDir)
      if fileExists(tempFontPath):
        removeFile(tempFontPath)
      if dirExists(tempDir):
        removeDir(tempDir)

    let id = loadTypeface(fontName)
    check id.int != 0
    check typefaceTable[id].filePath == tempFontPath

  test "loadTypeface falls back to system fonts":
    let oldDataDir = figDataDir()
    let emptyDir = getTempDir() / "figdraw-font-system-fallback-test"
    if not dirExists(emptyDir):
      createDir(emptyDir)
    setFigDataDir(emptyDir)
    defer:
      setFigDataDir(oldDataDir)
      if dirExists(emptyDir):
        removeDir(emptyDir)

    var candidates: seq[string]
    when defined(windows):
      candidates = @["Arial", "Segoe UI", "Tahoma", "Verdana", "Calibri"]
    elif defined(macosx):
      candidates = @["Helvetica", "Arial", "Menlo", "SFNS"]
    elif defined(linux) or defined(freebsd):
      candidates = @["DejaVu Sans", "Noto Sans", "Liberation Sans", "Ubuntu"]

    proc firstLoadableSystemFontPath(candidates: openArray[string]): string =
      let preferred = findSystemFontFile(candidates)
      if preferred.len > 0:
        try:
          discard readTypeface(preferred)
          return preferred
        except PixieError:
          discard

      for path in systemFontFiles():
        try:
          discard readTypeface(path)
          return path
        except PixieError:
          discard

      ""

    let systemPath = firstLoadableSystemFontPath(candidates)
    if systemPath.len == 0:
      check true
    else:
      let requestName = extractFilename(systemPath)
      let id = loadTypeface(requestName)
      check id.int != 0
      check typefaceTable[id].filePath.len > 0

  test "loadTypeface searches static registry via fallbackNames":
    let oldDataDir = figDataDir()
    let emptyDir = getTempDir() / "figdraw-font-embedded-fallback-test"
    if not dirExists(emptyDir):
      createDir(emptyDir)
    setFigDataDir(emptyDir)
    defer:
      setFigDataDir(oldDataDir)
      if dirExists(emptyDir):
        removeDir(emptyDir)

    registerStaticTypeface("test-ubuntu.ttf", "../data/Ubuntu.ttf", TTF)

    let missingName = "__figdraw_missing_font_for_embedded_fallback__.ttf"
    let id = loadTypeface(missingName, ["test-ubuntu.ttf"])
    check id.int != 0
    check typefaceTable[id].filePath == "test-ubuntu.ttf"
