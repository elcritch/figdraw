import std/[hashes, os, unittest, tables, locks, unicode]

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

when figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid":
  proc firstLoadableNamedSystemFontPath(candidates: openArray[string]): string =
    let preferred = findSystemFontFile(candidates)
    if preferred.len > 0:
      try:
        discard readTypeface(preferred)
        return preferred
      except PixieError:
        discard
    ""

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

    test "harfbuzzy wrap creates line slices at shaped glyph boundaries":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 24.0'f32)
      let box = rect(0, 0, 95, 200)
      let spans = [(fs(uiFont), "alpha beta gamma")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = true
      )

      check arrangement.lines.len > 1

      var covered = 0
      var previousStop = -1
      var previousY = -1.0'f32
      for line in arrangement.lines:
        check line.a == previousStop + 1
        check line.a <= line.b
        check line.b < arrangement.arrangedGlyphs.len

        var
          minX = float32.high
          maxX = -float32.high
          maxGlyphWidth = 0.0'f32
          minY = float32.high
        for glyphIndex in line:
          let glyph = arrangement.arrangedGlyphs[glyphIndex]
          minX = min(minX, glyph.rect.x)
          maxX = max(maxX, glyph.rect.x + glyph.rect.w)
          maxGlyphWidth = max(maxGlyphWidth, glyph.rect.w)
          minY = min(minY, glyph.rect.y)
          check glyph.source.runeStart >= 0
          check glyph.source.runeEnd <= arrangement.sourceRunes.len
          inc covered

        let lineWidth = maxX - minX
        check lineWidth <= box.w + 0.1'f32 or maxGlyphWidth > box.w
        check minY > previousY
        previousY = minY
        previousStop = line.b

      check covered == arrangement.arrangedGlyphs.len

    test "harfbuzzy wrap keeps ligature source ranges on one line":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
      let box = rect(0, 0, 78, 160)
      let spans = [(fs(uiFont), "office office")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = true
      )

      check arrangement.lines.len > 1
      let ligatureGlyph = arrangement.glyphRangeForSourceRunes(1 .. 3).a
      check ligatureGlyph >= 0
      check arrangement.sourceRuneRange(ligatureGlyph) == 1 .. 3

      var lineIndex = -1
      for i, line in arrangement.lines:
        if ligatureGlyph >= line.a and ligatureGlyph <= line.b:
          lineIndex = i
          break
      check lineIndex >= 0

      for glyphIndex in arrangement.glyphRangeForSourceRunes(1 .. 3):
        var glyphLineIndex = -1
        for i, line in arrangement.lines:
          if glyphIndex >= line.a and glyphIndex <= line.b:
            glyphLineIndex = i
            break
        check glyphLineIndex == lineIndex

    test "harfbuzzy minContent keeps bottom-aligned wrapped text in bounds":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 24.0'f32)
      let box = rect(0, 0, 82, 20)
      let spans = [(fs(uiFont), "alpha beta gamma delta")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Bottom, minContent = true, wrap = true
      )

      check arrangement.lines.len > 1
      check arrangement.bounding.y >= -0.01'f32
      check arrangement.minSize.y > box.h

    test "harfbuzzy mixed direction text preserves source hit ranges":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 28.0'f32)
      let box = rect(0, 0, 420, 80)
      let spans = [(fs(uiFont), "abc שלום xyz")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.sourceRunes.len == 12
      let hebrewGlyphRange = arrangement.glyphRangeForSourceRunes(4 .. 7)
      check hebrewGlyphRange.a >= 0
      check hebrewGlyphRange.b >= hebrewGlyphRange.a

      let rects = arrangement.selectionRectsForSourceRunes(4 .. 7)
      check rects.len == hebrewGlyphRange.b - hebrewGlyphRange.a + 1
      for rect in rects:
        let point = vec2(rect.x + rect.w / 2, rect.y + rect.h / 2)
        let sourceRange = arrangement.sourceRuneRangeAt(point)
        check sourceRange.a >= 4
        check sourceRange.b <= 7

    test "harfbuzzy wraps CJK text without whitespace":
      let fontPath = "deps/pixie/tests/fonts/NotoSansJP-Regular.ttf"
      if not fileExists(fontPath):
        check true
      else:
        let typefaceId = loadTypeface(fontPath)
        let uiFont = FigFont(typefaceId: typefaceId, size: 24.0'f32)
        let box = rect(0, 0, 72, 200)
        let spans = [(fs(uiFont), "日本語日本語日本語")]

        let arrangement = typeset(
          box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = true
        )

        check arrangement.lines.len > 1
        var previousStop = -1
        for line in arrangement.lines:
          check line.a == previousStop + 1
          check line.a <= line.b
          check line.b < arrangement.arrangedGlyphs.len

          var
            minX = float32.high
            maxX = -float32.high
          for glyphIndex in line:
            let glyph = arrangement.arrangedGlyphs[glyphIndex]
            minX = min(minX, glyph.rect.x)
            maxX = max(maxX, glyph.rect.x + glyph.rect.w)
            check not glyph.rune.isWhiteSpace

          check maxX - minX <= box.w + 0.1'f32
          previousStop = line.b

    test "harfbuzzy source helpers cover combining marks":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
      let acute = $Rune(0x0301)
      let box = rect(0, 0, 260, 80)
      let spans = [(fs(uiFont), "Cafe" & acute & " test")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.sourceRunes.len == 10
      let markGlyphRange = arrangement.glyphRangeForSourceRunes(4 .. 4)
      check markGlyphRange.a >= 0
      check markGlyphRange.b >= markGlyphRange.a

      let markRects = arrangement.selectionRectsForSourceRunes(4 .. 4)
      check markRects.len > 0
      for rect in markRects:
        let point = vec2(rect.x + rect.w / 2, rect.y + rect.h / 2)
        let sourceRange = arrangement.sourceRuneRangeAt(point)
        check sourceRange.a <= 4
        check sourceRange.b >= 4

      let carets = arrangement.caretPositionsForSourceRune(4)
      check carets.len > 0
      check arrangement.nearestSourceRuneForCaretPoint(carets[0].pos) == 4

    test "harfbuzzy source helpers cover Hebrew marks":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
      let text = "ש" & $Rune(0x05b8) & $Rune(0x05c1) & "לו" & $Rune(0x05b9) & "ם"
      let box = rect(0, 0, 260, 80)
      let spans = [(fs(uiFont), text)]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.sourceRunes.len == 7
      for markIndex in [1, 2, 5]:
        let markGlyphRange =
          arrangement.glyphRangeForSourceRunes(markIndex .. markIndex)
        check markGlyphRange.a >= 0
        check markGlyphRange.b >= markGlyphRange.a

        let markRects = arrangement.selectionRectsForSourceRunes(markIndex .. markIndex)
        check markRects.len > 0
        for rect in markRects:
          if rect.w > 0 and rect.h > 0:
            let point = vec2(rect.x + rect.w / 2, rect.y + rect.h / 2)
            let sourceRange = arrangement.sourceRuneRangeAt(point)
            check sourceRange.a <= markIndex
            check sourceRange.b >= markIndex

        let carets = arrangement.caretPositionsForSourceRune(markIndex)
        check carets.len > 0

    test "harfbuzzy caret helpers expose split mixed-direction positions":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 28.0'f32)
      let box = rect(0, 0, 420, 80)
      let spans = [(fs(uiFont), "abc שלום xyz")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      let hebrewStartCarets = arrangement.caretPositionsForSourceRune(4)
      check hebrewStartCarets.len > 0
      for caret in hebrewStartCarets:
        check caret.sourceRune == 4
        check caret.glyphIndex >= 0
        check caret.lineIndex == 0
        check arrangement.nearestSourceRuneForCaretPoint(caret.pos) == 4

      let hebrewEndCarets = arrangement.caretPositionsForSourceRune(8)
      check hebrewEndCarets.len > 0
      for caret in hebrewEndCarets:
        check caret.sourceRune == 8

    test "harfbuzzy shapes Arabic when a system Arabic font is available":
      let fontPath = firstLoadableNamedSystemFontPath(
        [
          "Noto Naskh Arabic", "Noto Sans Arabic", "Geeza Pro", "Arial Unicode",
          "Arial", "DejaVu Sans",
        ]
      )
      if fontPath.len == 0:
        check true
      else:
        let typefaceId = loadTypeface(fontPath)
        let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
        let box = rect(0, 0, 320, 90)
        let spans = [(fs(uiFont), "سلام")]

        let arrangement = typeset(
          box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
        )

        check arrangement.sourceRunes.len == 4
        check arrangement.arrangedGlyphs.len > 0
        check arrangement.arrangedGlyphs.len <= arrangement.sourceRunes.len
        for glyph in arrangement.arrangedGlyphs:
          check glyph.glyphId != FontGlyphId(0)
          check glyph.source.runeStart >= 0
          check glyph.source.runeEnd <= arrangement.sourceRunes.len

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

  test "glyph iterator skips empty spans before assigning style":
    let
      rune = "A".runeAt(0)
      fontId = FontId(Hash(1))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 12, descentAdj: 3)
      firstFill = fill(rgba(220, 40, 40, 255))
      secondFill = fill(rgba(40, 90, 220, 255))
      arrangement = GlyphArrangement(
        lines: @[0 .. 0],
        spans: @[0 .. -1, 0 .. 0],
        fonts: @[glyphFont, glyphFont],
        spanColors: @[firstFill, secondFill],
        sourceRunes: @[rune],
        arrangedGlyphs:
          @[
            ArrangedGlyph(
              fontId: fontId,
              glyphId: FontGlyphId(65),
              cluster: 0,
              source:
                GlyphSourceRange(byteStart: 0, byteEnd: 1, runeStart: 0, runeEnd: 1),
              rune: rune,
              pos: vec2(10, 12),
              rect: rect(10, 0, 8, 12),
            )
          ],
      )

    var glyphs = newSeq[GlyphPosition]()
    for glyph in arrangement.glyphs():
      glyphs.add glyph

    check glyphs.len == 1
    check glyphs[0].fill == secondFill
    check glyphs[0].lineHeight == glyphFont.lineHeight

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
