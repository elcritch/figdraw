import std/[hashes, os, tables, unicode, unittest]

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

proc drainImageMessages() =
  var msg: ImageMsg
  while tryRecvImageMsg(msg):
    discard

proc recvImageMsg(kind: ImageMsgKind): ImageMsg =
  require tryRecvImageMsg(result)
  check result.kind == kind

template registerStaticDefaultSansTypeface(path: static[string]) =
  when defined(windows):
    registerStaticTypeface("Segoe UI", path, TTF)
  elif defined(macosx):
    registerStaticTypeface("Helvetica", path, TTF)
  elif defined(posix):
    registerStaticTypeface("Noto Sans", path, TTF)
  else:
    discard

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
  proc firstLoadableNamedSystemFontPath(
      candidates: openArray[string], requiredText: string
  ): string =
    proc supportsRequiredRunes(typeface: Typeface): bool =
      for rune in requiredText.runes:
        if not typeface.hasGlyph(rune):
          return false
      true

    let preferred = findSystemFontFile(candidates)
    if preferred.len > 0:
      try:
        if readTypeface(preferred).supportsRequiredRunes():
          return preferred
      except PixieError:
        discard

    for path in systemFontFiles():
      try:
        if readTypeface(path).supportsRequiredRunes():
          return path
      except PixieError:
        discard
    ""

proc testGlyph(
    fontId: FontId, sourceRune: int, glyphId: uint32, box: Rect
): ArrangedGlyph =
  let rune = Rune(0x61'i32 + sourceRune.int32)
  ArrangedGlyph(
    fontId: fontId,
    glyphId: FontGlyphId(glyphId),
    source: GlyphSourceRange(
      byteStart: sourceRune,
      byteEnd: sourceRune + 1,
      runeStart: sourceRune,
      runeEnd: sourceRune + 1,
    ),
    rune: rune,
    pos: box.xy,
    rect: box,
  )

proc testGlyphRange(
    fontId: FontId, sourceRange: Slice[int], glyphId: uint32, box: Rect
): ArrangedGlyph =
  let rune = Rune(0x61'i32 + sourceRange.a.int32)
  ArrangedGlyph(
    fontId: fontId,
    glyphId: FontGlyphId(glyphId),
    source: GlyphSourceRange(
      byteStart: sourceRange.a,
      byteEnd: sourceRange.b + 1,
      runeStart: sourceRange.a,
      runeEnd: sourceRange.b + 1,
    ),
    rune: rune,
    pos: box.xy,
    rect: box,
  )

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

  test "typeface metadata is parsed and cached with the registered face":
    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      info = getTypefaceInfo(typefaceId)

    check info.family == "Ubuntu"
    check info.subfamily == "Regular"
    check info.fullName.len > 0
    check info.postScriptName.len > 0
    check info.faceIndex == 0
    check info.weightClass == 400
    check info.widthClass == 5
    check info.regular
    check not info.bold
    check not info.italic
    check info.localizedNames.len > 0
    check "latn" in info.layoutScripts

    var hasEnglishName = false
    for name in info.localizedNames:
      if name.languageTag == "en-US":
        hasEnglishName = true
    check hasEnglishName

    var changed = info
    changed.layoutScripts[0] = "changed"
    check "changed" notin getTypefaceInfo(typefaceId).layoutScripts

  test "typeface metadata exposes variable axes and shaping scripts":
    let
      fontPath = getCurrentDir() / "examples/fonts/NotoNaskhArabic-wght.ttf"
      typefaceId = loadTypeface(fontPath)
      info = getTypefaceInfo(typefaceId)

    check info.family == "Noto Naskh Arabic"
    check info.variationAxes.len == 1
    check info.variationAxes[0].tag == "wght"
    check info.variationAxes[0].name == "Weight"
    check info.variationAxes[0].minValue == 400.0'f32
    check info.variationAxes[0].defaultValue == 400.0'f32
    check info.variationAxes[0].maxValue == 700.0'f32
    check "arab" in info.layoutScripts

  test "unknown typeface metadata lookup raises ValueError":
    expect ValueError:
      discard getTypefaceInfo(TypefaceId(Hash(9_999_999)))

  test "typeface ids distinguish different bytes with the same name":
    let
      ubuntuData = readFile(figDataDir() / "Ubuntu.ttf")
      hackData = readFile(figDataDir() / "HackNerdFont-Regular.ttf")
      ubuntuId = loadTypeface("same-name.ttf", ubuntuData, TTF)
      hackId = loadTypeface("same-name.ttf", hackData, TTF)

    check ubuntuId != hackId
    check getTypefaceSource(ubuntuId).data == ubuntuData
    check getTypefaceSource(hackId).data == hackData

  test "typeface ids reuse identical bytes loaded through aliases":
    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      firstId = loadTypeface("first-name.ttf", fontData, TTF)
      secondId = loadTypeface("second-name.ttf", fontData, TTF)

    check firstId == secondId

  test "convertFont caches pixie font":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 20.0'f32)

    let fontId1 = uiFont.convertFont()[0]
    let fontId2 = uiFont.convertFont()[0]

    check fontId1 == fontId2
    check fontId1 in fontTable

  test "raster font ids ignore shaping-only settings":
    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      baseFont = FigFont(typefaceId: typefaceId, size: 20.0'f32)
      shapingFont = FigFont(
        typefaceId: typefaceId,
        size: 20.0'f32,
        fallbackTypefaceIds: @[typefaceId],
        features: @[fontFeature("liga", 0)],
        noKerningAdjustments: true,
        underline: true,
      )

    check baseFont.convertFont()[0] == shapingFont.convertFont()[0]

  test "layout content hashes include wrapping policy":
    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      uiFont = FigFont(typefaceId: typefaceId, size: 20.0'f32)
      spans = [(fs(uiFont), "alpha beta")]
      size = vec2(100, 40)

    check getContentHash(size, spans, Left, Top, false, false) !=
      getContentHash(size, spans, Left, Top, false, true)
    check getContentHash(size, spans, Left, Top, false, true) !=
      getContentHash(size, spans, Left, Top, true, true)

  test "lineHeight affects computed lineHeight":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)

    let (_, pf) = uiFont.convertFont()
    let expected = pf.defaultLineHeight()

    check abs(pf.lineHeight - expected) < 0.01'f32
    check abs(getLineHeightImpl(uiFont).scaled() - expected) < 0.01'f32

  test "text decorations are carried into glyph font spans":
    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      uiFont = FigFont(
        typefaceId: typefaceId, size: 24.0'f32, underline: true, strikethrough: true
      )
      arrangement = typeset(
        rect(0, 0, 200, 60), [(fs(uiFont), "Decorated")], Left, Top, false, false
      )

    check arrangement.fonts.len > 0
    for font in arrangement.fonts:
      check font.size == uiFont.size
      check font.underline
      check font.strikethrough

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

  test "measurement-only typesetting does not publish glyph images":
    let
      fontData = readFile(figDataDir() / "Ubuntu.ttf")
      typefaceId = loadTypeface("measurement-only.ttf", fontData, TTF)
      uiFont = FigFont(typefaceId: typefaceId, size: 19.0'f32)
    clearImageCache()
    let messages = newImageMessageSubscription()
    let arrangement = typesetForMeasurement(
      rect(0, 0, 240, 60), uiFont, "Measure me", Left, Top, false, false
    )

    check arrangement.bounding.w > 0.0'f32
    var msg: ImageMsg
    check not messages.tryRecvImageMsg(msg)

  test "source selection bands use full line height":
    let
      fontId = FontId(Hash(42))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 14, descentAdj: 10)
      sourceRunes = @["a".runeAt(0), "b".runeAt(0), "c".runeAt(0), "d".runeAt(0)]
      arrangement = GlyphArrangement(
        lines: @[0 .. 3],
        spans: @[0 .. 3],
        fonts: @[glyphFont],
        sourceRunes: sourceRunes,
        arrangedGlyphs:
          @[
            testGlyph(fontId, 0, 10, rect(0, 2, 12, 10)),
            testGlyph(fontId, 1, 11, rect(12, 4, 8, 6)),
            testGlyph(fontId, 2, 12, rect(20, 0, 10, 14)),
            testGlyph(fontId, 3, 13, rect(30, 2, 10, 10)),
          ],
        runes: sourceRunes,
        selectionRects:
          @[
            rect(0, 2, 12, 10),
            rect(12, 4, 8, 6),
            rect(20, 0, 10, 14),
            rect(30, 2, 10, 10),
          ],
      )

    let rawRects = arrangement.glyphSelectionRectsFor(1 .. 2)
    check rawRects == @[rect(12, 4, 8, 6), rect(20, 0, 10, 14)]

    let bands = arrangement.selectionRectsFor(1 .. 2)
    check bands == @[rect(12, 0, 18, 14)]
    check arrangement.selectionBandsFor(1 .. 2) == bands
    check arrangement.selectionRectsForRawBytes(1 .. 2) == bands

  test "source selection bands split separated visual fragments":
    let
      fontId = FontId(Hash(43))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 14, descentAdj: 10)
      sourceRunes =
        @["a".runeAt(0), "b".runeAt(0), "c".runeAt(0), "d".runeAt(0), "e".runeAt(0)]
      arrangement = GlyphArrangement(
        lines: @[0 .. 4],
        spans: @[0 .. 4],
        fonts: @[glyphFont],
        sourceRunes: sourceRunes,
        arrangedGlyphs:
          @[
            testGlyph(fontId, 0, 10, rect(0, 0, 10, 14)),
            testGlyph(fontId, 1, 11, rect(10, 0, 10, 14)),
            testGlyph(fontId, 3, 13, rect(20, 0, 10, 14)),
            testGlyph(fontId, 2, 12, rect(30, 0, 10, 14)),
            testGlyph(fontId, 4, 14, rect(40, 0, 10, 14)),
          ],
        runes: sourceRunes,
        selectionRects:
          @[
            rect(0, 0, 10, 14),
            rect(10, 0, 10, 14),
            rect(20, 0, 10, 14),
            rect(30, 0, 10, 14),
            rect(40, 0, 10, 14),
          ],
      )

    let rawRects = arrangement.glyphSelectionRectsFor(1 .. 2)
    check rawRects == @[rect(10, 0, 10, 14), rect(30, 0, 10, 14)]
    check arrangement.selectionRectsFor(1 .. 2) ==
      @[rect(10, 0, 10, 14), rect(30, 0, 10, 14)]

  test "source selection bands clip partial ligature ranges":
    let
      fontId = FontId(Hash(44))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 14, descentAdj: 10)
      sourceRunes = @["a".runeAt(0), "b".runeAt(0), "c".runeAt(0), "d".runeAt(0)]
      arrangement = GlyphArrangement(
        lines: @[0 .. 0],
        spans: @[0 .. 0],
        fonts: @[glyphFont],
        sourceRunes: sourceRunes,
        arrangedGlyphs: @[testGlyphRange(fontId, 0 .. 3, 20, rect(10, 2, 40, 10))],
        runes: sourceRunes,
        selectionRects: @[rect(10, 2, 40, 10)],
      )

    check arrangement.glyphSelectionRectsFor(1 .. 1) == @[rect(10, 2, 40, 10)]
    check arrangement.selectionRectsFor(1 .. 1) == @[rect(20, 2, 10, 10)]
    check arrangement.selectionRectsFor(1 .. 2) == @[rect(20, 2, 20, 10)]

  test "source selection bands clip rtl partial ligature ranges from right edge":
    let
      fontId = FontId(Hash(45))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 14, descentAdj: 10)
      sourceRunes =
        @["a".runeAt(0), "b".runeAt(0), "c".runeAt(0), "d".runeAt(0), "e".runeAt(0)]
      arrangement = GlyphArrangement(
        lines: @[0 .. 2],
        spans: @[0 .. 2],
        fonts: @[glyphFont],
        sourceRunes: sourceRunes,
        arrangedGlyphs:
          @[
            testGlyph(fontId, 4, 24, rect(0, 0, 10, 14)),
            testGlyphRange(fontId, 1 .. 3, 21, rect(10, 0, 30, 14)),
            testGlyph(fontId, 0, 20, rect(40, 0, 10, 14)),
          ],
        runes: sourceRunes,
        selectionRects: @[rect(0, 0, 10, 14), rect(10, 0, 30, 14), rect(40, 0, 10, 14)],
      )

    check arrangement.selectionRectsFor(1 .. 1) == @[rect(30, 0, 10, 14)]
    check arrangement.selectionRectsFor(2 .. 3) == @[rect(10, 0, 20, 14)]

  test "caret positions collapse ltr shaped cluster fragments":
    let
      fontId = FontId(Hash(46))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 14, descentAdj: 10)
      sourceRunes = @["a".runeAt(0), "b".runeAt(0), "c".runeAt(0), "d".runeAt(0)]
      arrangement = GlyphArrangement(
        lines: @[0 .. 3],
        spans: @[0 .. 3],
        fonts: @[glyphFont],
        sourceRunes: sourceRunes,
        arrangedGlyphs:
          @[
            testGlyph(fontId, 0, 10, rect(0, 0, 10, 14)),
            testGlyphRange(fontId, 1 .. 2, 21, rect(22, 0, 0, 14)),
            testGlyphRange(fontId, 1 .. 2, 22, rect(10, 0, 20, 14)),
            testGlyph(fontId, 3, 13, rect(30, 0, 10, 14)),
          ],
        runes: sourceRunes,
        selectionRects:
          @[
            rect(0, 0, 10, 14),
            rect(22, 0, 0, 14),
            rect(10, 0, 20, 14),
            rect(30, 0, 10, 14),
          ],
      )

    let
      startCarets = arrangement.caretPositionsFor(1)
      insideCarets = arrangement.caretPositionsFor(2)
      endCarets = arrangement.caretPositionsFor(3)

    check startCarets.len == 1
    check abs(startCarets[0].pos.x - 10.0'f32) < 0.01'f32
    check insideCarets.len == 1
    check abs(insideCarets[0].pos.x - 20.0'f32) < 0.01'f32
    check endCarets.len == 1
    check abs(endCarets[0].pos.x - 30.0'f32) < 0.01'f32
    check arrangement.selectionRectsFor(1 .. 1) == @[rect(10, 0, 10, 14)]

  test "caret positions collapse rtl shaped cluster fragments":
    let
      fontId = FontId(Hash(47))
      glyphFont = GlyphFont(fontId: fontId, lineHeight: 14, descentAdj: 10)
      sourceRunes =
        @["a".runeAt(0), "b".runeAt(0), "c".runeAt(0), "d".runeAt(0), "e".runeAt(0)]
      arrangement = GlyphArrangement(
        lines: @[0 .. 3],
        spans: @[0 .. 3],
        fonts: @[glyphFont],
        sourceRunes: sourceRunes,
        arrangedGlyphs:
          @[
            testGlyph(fontId, 4, 14, rect(0, 0, 10, 14)),
            testGlyphRange(fontId, 1 .. 2, 21, rect(22, 0, 0, 14)),
            testGlyphRange(fontId, 1 .. 2, 22, rect(10, 0, 20, 14)),
            testGlyph(fontId, 0, 10, rect(30, 0, 10, 14)),
          ],
        runes: sourceRunes,
        selectionRects:
          @[
            rect(0, 0, 10, 14),
            rect(22, 0, 0, 14),
            rect(10, 0, 20, 14),
            rect(30, 0, 10, 14),
          ],
      )

    let
      startCarets = arrangement.caretPositionsFor(1)
      insideCarets = arrangement.caretPositionsFor(2)
      endCarets = arrangement.caretPositionsFor(3)

    check startCarets.len == 1
    check abs(startCarets[0].pos.x - 30.0'f32) < 0.01'f32
    check insideCarets.len == 1
    check abs(insideCarets[0].pos.x - 20.0'f32) < 0.01'f32
    check endCarets.len == 1
    check abs(endCarets[0].pos.x - 10.0'f32) < 0.01'f32
    check arrangement.selectionRectsFor(2 .. 2) == @[rect(10, 0, 10, 14)]

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

      let ligatureGlyphRange = arrangement.glyphRangeFor(1 .. 3)
      check ligatureGlyphRange.a == ligatureGlyphRange.b

      let ligatureGlyph = ligatureGlyphRange.a
      check arrangement.sourceRuneRange(ligatureGlyph) == 1 .. 3

      var source = ""
      for rune in sourceRunes(arrangement, ligatureGlyph):
        source.add $rune
      check source == "ffi"

      let rects = arrangement.glyphSelectionRectsFor(2 .. 2)
      check rects.len == 1
      check rects[0] == arrangement.arrangedGlyphs[ligatureGlyph].rect
      check arrangement.selectionRectsFor(2 .. 2).len == 1

      let hitPoint = vec2(rects[0].x + rects[0].w / 2, rects[0].y + rects[0].h / 2)
      check arrangement.glyphIndexAt(hitPoint) == ligatureGlyph
      check arrangement.sourceRuneRangeAt(hitPoint) == 1 .. 3

    test "paint-only span boundaries preserve shaping continuity":
      let
        fontData = readFile(figDataDir() / "Ubuntu.ttf")
        typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
        uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
        box = rect(0, 0, 300, 80)
        whole = typeset(box, [(fs(uiFont), "office")], Left, Top, false, false)
        split = typeset(
          box,
          [
            (fs(uiFont, rgba(220, 40, 40, 255).color), "of"),
            (fs(uiFont, rgba(40, 90, 220, 255).color), "fice"),
          ],
          Left,
          Top,
          false,
          false,
        )

      check split.arrangedGlyphs.len == whole.arrangedGlyphs.len
      check split.glyphRangeFor(1 .. 3).len == 1
      check split.spans.len == 2
      check split.spanColors.len == 2

    test "font case preserves original source text and byte ranges":
      let
        fontData = readFile(figDataDir() / "Ubuntu.ttf")
        typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
        source = "a" & $Rune(0x017f) & "b"
        uiFont = FigFont(typefaceId: typefaceId, size: 28.0'f32, fontCase: UpperCase)
        arrangement =
          typeset(rect(0, 0, 240, 60), [(fs(uiFont), source)], Left, Top, false, false)

      check arrangement.sourceRunes == source.toRunes()
      check arrangement.glyphRangeForRawBytes(1 .. 2).len > 0

    test "OpenType features can disable discretionary ligature shaping":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(
        typefaceId: typefaceId,
        size: 32.0'f32,
        features: @[fontFeature("liga", 0), fontFeature("clig", 0)],
      )
      let box = rect(0, 0, 300, 80)
      let spans = [(fs(uiFont), "office")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.sourceRunes.len == 6
      check arrangement.arrangedGlyphs.len == arrangement.sourceRunes.len

      let glyphRange = arrangement.glyphRangeFor(1 .. 3)
      check glyphRange.b - glyphRange.a + 1 == 3

    test "harfbuzzy fallback stores fallback font ids on shaped runs":
      let
        primaryId = loadTypeface(
          getCurrentDir() / "examples/fonts" / "NotoSansHebrew-wdth-wght.ttf"
        )
        arabicId =
          loadTypeface(getCurrentDir() / "examples/fonts" / "NotoNaskhArabic-wght.ttf")
        uiFont = FigFont(
          typefaceId: primaryId, size: 32.0'f32, fallbackTypefaceIds: @[arabicId]
        )
        box = rect(0, 0, 360, 90)
        spans = [(fs(uiFont), "abc سلام")]

      let arrangement = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check arrangement.spans.len == arrangement.fonts.len
      check arrangement.spans.len == arrangement.spanColors.len

      var sawArabicFallback = false
      for glyph in arrangement.arrangedGlyphs:
        var sourceHasArabic = false
        for sourceIndex in glyph.source.runeStart ..< glyph.source.runeEnd:
          let codepoint = arrangement.sourceRunes[sourceIndex].uint32
          if codepoint in 0x0600'u32 .. 0x06ff'u32:
            sourceHasArabic = true
            break

        if sourceHasArabic:
          check getFigFont(glyph.fontId).typefaceId == arabicId
          sawArabicFallback = true

      check sawArabicFallback

    test "variable axes are carried by shaped font ids":
      let typefaceId = loadTypeface(
        getCurrentDir() / "examples/fonts" / "NotoSansHebrew-wdth-wght.ttf"
      )
      let lightFont = FigFont(
        typefaceId: typefaceId,
        size: 32.0'f32,
        variations: @[fontVariation("wght", 300.0'f32), fontVariation("wdth", 90.0'f32)],
      )
      let boldFont = FigFont(
        typefaceId: typefaceId,
        size: 32.0'f32,
        variations:
          @[fontVariation("wght", 800.0'f32), fontVariation("wdth", 100.0'f32)],
      )
      let box = rect(0, 0, 300, 80)

      let
        lightArrangement = typeset(
          box,
          [(fs(lightFont), "שלום")],
          hAlign = Left,
          vAlign = Top,
          minContent = false,
          wrap = false,
        )
        boldArrangement = typeset(
          box,
          [(fs(boldFont), "שלום")],
          hAlign = Left,
          vAlign = Top,
          minContent = false,
          wrap = false,
        )

      check lightArrangement.arrangedGlyphs.len == boldArrangement.arrangedGlyphs.len
      check lightArrangement.arrangedGlyphs.len > 0
      check lightArrangement.arrangedGlyphs[0].fontId !=
        boldArrangement.arrangedGlyphs[0].fontId
      check getFigFont(lightArrangement.arrangedGlyphs[0].fontId).variations ==
        lightFont.variations
      check getFigFont(boldArrangement.arrangedGlyphs[0].fontId).variations ==
        boldFont.variations

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

    test "harfbuzzy wraps long text to fit the layout box":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
      let box = rect(0, 0, 160, 400)
      let spans = [
        (
          fs(uiFont),
          "This is a long sentence that should wrap across several lines " &
            "when the layout box is much narrower than the unwrapped text.",
        )
      ]

      let wrapped = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = true
      )
      let unwrapped = typeset(
        box, spans, hAlign = Left, vAlign = Top, minContent = false, wrap = false
      )

      check unwrapped.lines.len == 1
      check wrapped.lines.len > 1
      check wrapped.bounding.w <= box.w + 0.1'f32
      check wrapped.bounding.h > unwrapped.bounding.h

      for line in wrapped.lines:
        var
          minX = float32.high
          maxX = -float32.high
          glyphCount = 0

        for glyphIndex in line:
          let glyph = wrapped.arrangedGlyphs[glyphIndex]
          minX = min(minX, glyph.rect.x)
          maxX = max(maxX, glyph.rect.x + glyph.rect.w)
          inc glyphCount

        check glyphCount > 0
        check maxX - minX <= box.w + 0.1'f32

    test "harfbuzzy hard line breaks do not render newline glyphs":
      let fontData = readFile(figDataDir() / "Ubuntu.ttf")
      let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
      let uiFont = FigFont(typefaceId: typefaceId, size: 24.0'f32)
      let box = rect(0, 0, 260, 120)
      let text = "alpha\nbeta"

      let arrangement = typeset(
        box,
        [(fs(uiFont), text)],
        hAlign = Left,
        vAlign = Top,
        minContent = false,
        wrap = false,
      )

      check arrangement.sourceRunes.len == 10
      check arrangement.lines.len == 2
      for glyph in arrangement.arrangedGlyphs:
        check glyph.rune != Rune(10)

      var lineY: array[2, float32]
      for i, line in arrangement.lines:
        lineY[i] = float32.high
        for glyphIndex in line:
          lineY[i] = min(lineY[i], arrangement.arrangedGlyphs[glyphIndex].rect.y)
      check lineY[0] < lineY[1]

    test "harfbuzzy preserves empty hard-break lines":
      let
        fontData = readFile(figDataDir() / "Ubuntu.ttf")
        typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
        uiFont = FigFont(typefaceId: typefaceId, size: 24.0'f32)
        arrangement = typeset(
          rect(0, 0, 260, 180), [(fs(uiFont), "a\n\nb")], Left, Top, false, false
        )

      check arrangement.lines.len == 3
      check arrangement.lines[1].len == 1
      let
        firstLine = arrangement.arrangedGlyphs[arrangement.lines[0].a].rect
        emptyLine = arrangement.arrangedGlyphs[arrangement.lines[1].a].rect
        lastLine = arrangement.arrangedGlyphs[arrangement.lines[2].a].rect
      check emptyLine.w == 0
      check emptyLine.h > 0
      check firstLine.y < emptyLine.y
      check emptyLine.y < lastLine.y

    test "noKerningAdjustments disables Harfbuzz kerning":
      let
        fontData = readFile(figDataDir() / "Ubuntu.ttf")
        typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
        defaultFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
        noKerningFont =
          FigFont(typefaceId: typefaceId, size: 32.0'f32, noKerningAdjustments: true)
        box = rect(0, 0, 240, 80)
        defaultLayout = typeset(box, [(fs(defaultFont), "AV")], Left, Top, false, false)
        noKerningLayout =
          typeset(box, [(fs(noKerningFont), "AV")], Left, Top, false, false)

      check noKerningLayout.bounding.w > defaultLayout.bounding.w

    test "harfbuzzy wrapped Hebrew lines stay in logical order":
      let fontPath =
        getCurrentDir() / "examples" / "fonts" / "NotoSansHebrew-wdth-wght.ttf"
      require fileExists(fontPath)

      let typefaceId = loadTypeface(fontPath)
      let uiFont = FigFont(typefaceId: typefaceId, size: 24.0'f32)
      let box = rect(0, 0, 145, 260)
      let spans = [
        (
          fs(uiFont),
          "אחד שנים שלשה ארבעה חמשה ששה שבעה שמונה תשעה עשרה",
        )
      ]

      let arrangement = typeset(
        box, spans, hAlign = Right, vAlign = Top, minContent = false, wrap = true
      )

      check arrangement.lines.len > 1

      var previousLineStart = -1
      for line in arrangement.lines:
        var
          lineStart = high(int)
          lineY = float32.high
        for glyphIndex in line:
          let glyph = arrangement.arrangedGlyphs[glyphIndex]
          if glyph.source.runeStart < glyph.source.runeEnd:
            lineStart = min(lineStart, glyph.source.runeStart)
          lineY = min(lineY, glyph.rect.y)

        check lineStart >= previousLineStart
        check lineY < float32.high
        previousLineStart = lineStart

    test "harfbuzzy Hebrew hard line breaks stay in logical order":
      let fontPath =
        getCurrentDir() / "examples" / "fonts" / "NotoSansHebrew-wdth-wght.ttf"
      require fileExists(fontPath)

      let typefaceId = loadTypeface(fontPath)
      let uiFont = FigFont(
        typefaceId: typefaceId,
        size: 24.0'f32,
        features: @[fontFeature("kern"), fontFeature("liga"), fontFeature("mark")],
      )
      let box = rect(0, 0, 145, 260)
      let spans = [
        (
          fs(uiFont),
          "אחד שנים שלשה\nארבעה חמשה ששה שבעה שמונה",
        )
      ]

      let arrangement = typeset(
        box, spans, hAlign = Right, vAlign = Top, minContent = false, wrap = true
      )

      check arrangement.lines.len > 1

      var previousLineStart = -1
      for line in arrangement.lines:
        var lineStart = high(int)
        for glyphIndex in line:
          let glyph = arrangement.arrangedGlyphs[glyphIndex]
          check glyph.rune != Rune(10)
          if glyph.source.runeStart < glyph.source.runeEnd:
            lineStart = min(lineStart, glyph.source.runeStart)

        check lineStart >= previousLineStart
        previousLineStart = lineStart

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
      let ligatureGlyph = arrangement.glyphRangeFor(1 .. 3).a
      check ligatureGlyph >= 0
      check arrangement.sourceRuneRange(ligatureGlyph) == 1 .. 3

      var lineIndex = -1
      for i, line in arrangement.lines:
        if ligatureGlyph >= line.a and ligatureGlyph <= line.b:
          lineIndex = i
          break
      check lineIndex >= 0

      for glyphIndex in arrangement.glyphRangeFor(1 .. 3):
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
      let hebrewGlyphRange = arrangement.glyphRangeFor(4 .. 7)
      check hebrewGlyphRange.a >= 0
      check hebrewGlyphRange.b >= hebrewGlyphRange.a

      let rects = arrangement.glyphSelectionRectsFor(4 .. 7)
      check rects.len == hebrewGlyphRange.b - hebrewGlyphRange.a + 1
      check arrangement.selectionRectsFor(4 .. 7).len > 0
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
      let markGlyphRange = arrangement.glyphRangeFor(4 .. 4)
      check markGlyphRange.a >= 0
      check markGlyphRange.b >= markGlyphRange.a

      let markRects = arrangement.glyphSelectionRectsFor(4 .. 4)
      check markRects.len > 0
      check arrangement.selectionRectsFor(4 .. 4).len > 0
      for rect in markRects:
        let point = vec2(rect.x + rect.w / 2, rect.y + rect.h / 2)
        let sourceRange = arrangement.sourceRuneRangeAt(point)
        check sourceRange.a <= 4
        check sourceRange.b >= 4

      let carets = arrangement.caretPositionsFor(4)
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
        let markGlyphRange = arrangement.glyphRangeFor(markIndex .. markIndex)
        check markGlyphRange.a >= 0
        check markGlyphRange.b >= markGlyphRange.a

        let markRects = arrangement.glyphSelectionRectsFor(markIndex .. markIndex)
        check markRects.len > 0
        check arrangement.selectionRectsFor(markIndex .. markIndex).len > 0
        for rect in markRects:
          if rect.w > 0 and rect.h > 0:
            let point = vec2(rect.x + rect.w / 2, rect.y + rect.h / 2)
            let sourceRange = arrangement.sourceRuneRangeAt(point)
            check sourceRange.a <= markIndex
            check sourceRange.b >= markIndex

        let carets = arrangement.caretPositionsFor(markIndex)
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

      let hebrewStartCarets = arrangement.caretPositionsFor(4)
      check hebrewStartCarets.len > 0
      for caret in hebrewStartCarets:
        check caret.sourceRune == 4
        check caret.glyphIndex >= 0
        check caret.lineIndex == 0
        check arrangement.nearestSourceRuneForCaretPoint(caret.pos) == 4

      let hebrewEndCarets = arrangement.caretPositionsFor(8)
      check hebrewEndCarets.len > 0
      for caret in hebrewEndCarets:
        check caret.sourceRune == 8

    test "harfbuzzy shapes Arabic when a system Arabic font is available":
      const arabicText = "سلام"
      let fontPath = firstLoadableNamedSystemFontPath(
        [
          "Noto Naskh Arabic", "Noto Sans Arabic", "Geeza Pro", "Arial Unicode",
          "Arial", "DejaVu Sans",
        ],
        arabicText,
      )
      if fontPath.len == 0:
        check true
      else:
        let typefaceId = loadTypeface(fontPath)
        let uiFont = FigFont(typefaceId: typefaceId, size: 32.0'f32)
        let box = rect(0, 0, 320, 90)
        let spans = [(fs(uiFont), arabicText)]

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
      let glyphIndex = arrangement.glyphRangeFor(1 .. 3).a

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

  test "clearImageCache clears glyph markers and allows regeneration":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let arrangement = placeGlyphs(uiFont, [("A".runeAt(0), vec2(12, 16))])

    var glyphImageId = ImageId(0)
    for glyph in arrangement.glyphs():
      glyphImageId = glyph.hash().ImageId
      break
    require glyphImageId != ImageId(0)
    require hasImage(glyphImageId)

    clearImageCache()
    check not hasImage(glyphImageId)

    for glyph in arrangement.glyphs():
      discard glyph.generateGlyph()
      break
    check hasImage(glyphImageId)

  test "targeted glyph clears remove glyph markers and allow regeneration":
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    let arrangement = placeGlyphs(uiFont, [("B".runeAt(0), vec2(12, 16))])

    var glyphImageId = ImageId(0)
    for glyph in arrangement.glyphs():
      glyphImageId = glyph.hash().ImageId
      break
    require glyphImageId != ImageId(0)
    require hasImage(glyphImageId)

    clearFontGlyphs(uiFont)
    check not hasImage(glyphImageId)

    for glyph in arrangement.glyphs():
      discard glyph.generateGlyph()
      break
    require hasImage(glyphImageId)

    clearTypefaceGlyphs(typefaceId)
    check not hasImage(glyphImageId)

    for glyph in arrangement.glyphs():
      discard glyph.generateGlyph()
      break
    check hasImage(glyphImageId)

  test "FontRef copies share one retained handle":
    drainImageMessages()
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)

    var owner = fontRef(uiFont)
    let retain = recvImageMsg(ImkRetainFont)
    check retain.fontId == owner.fontId

    var copied = owner
    check copied == owner
    var msg: ImageMsg
    check not tryRecvImageMsg(msg)

    var moved = move(copied)
    check copied.isNil
    check not tryRecvImageMsg(msg)

    owner = nil
    check not tryRecvImageMsg(msg)

    moved = nil
    let release = recvImageMsg(ImkReleaseFont)
    check release.fontId == retain.fontId
    check release.ownerToken == retain.ownerToken

  test "FontRefs for the same ID share backend ownership":
    drainImageMessages()
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)

    var first = fontRef(uiFont)
    let retain = recvImageMsg(ImkRetainFont)

    var second = fontRef(uiFont)
    var msg: ImageMsg
    check not tryRecvImageMsg(msg)

    first = nil
    check not tryRecvImageMsg(msg)

    second = nil
    let release = recvImageMsg(ImkReleaseFont)
    check release.fontId == retain.fontId
    check release.ownerToken == retain.ownerToken

  test "FontRef works with text helper overloads":
    drainImageMessages()
    let fontData = readFile(figDataDir() / "Ubuntu.ttf")
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    var owner = fontRef(typefaceId, 18.0'f32)

    let
      style = fs(owner, fill(rgba(20, 30, 40, 255)))
      fontSpan = span(owner, fill(rgba(50, 60, 70, 255)), "Hello")
      fontStyleSpan = fsp(owner, fill(rgba(80, 90, 100, 255)), "World")
      layout = typeset(
        rect(0, 0, 200, 40),
        [span(owner, fill(rgba(20, 20, 20, 255)), "Hello")],
        minContent = false,
        wrap = true,
      )
      directLayout = typeset(
        rect(0, 0, 200, 40), [(owner, "Hello")], minContent = false, wrap = true
      )
      placed = placeGlyphs(owner, [("A".runeAt(0), vec2(0, 0))])

    check style.font == owner.font
    check style.color == fill(rgba(20, 30, 40, 255))
    check fontSpan[0].font == owner.font
    check fontSpan[1] == "Hello"
    check fontStyleSpan[0].font == owner.font
    check fontStyleSpan[1] == "World"
    check layout.runes.len > 0
    check directLayout.runes.len > 0
    check placed.runes.len == 1

    clearFontGlyphs(owner)
    owner = nil
    drainImageMessages()

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

  test "loadTypeface falls back to platform default font names":
    if systemDefaultFontNames().len == 0:
      check true
    else:
      let oldDataDir = figDataDir()
      let emptyDir = getTempDir() / "figdraw-font-default-fallback-test"
      if not dirExists(emptyDir):
        createDir(emptyDir)
      setFigDataDir(emptyDir)
      defer:
        setFigDataDir(oldDataDir)
        if dirExists(emptyDir):
          removeDir(emptyDir)

      registerStaticDefaultSansTypeface("../data/Ubuntu.ttf")

      let missingName = "__figdraw_missing_font_for_platform_default__.ttf"
      let id = loadTypeface(missingName)
      check id.int != 0
      check typefaceTable[id].filePath != missingName

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

    registerStaticDefaultSansTypeface("../data/Ubuntu.ttf")
    registerStaticTypeface("test-ubuntu.ttf", "../data/Ubuntu.ttf", TTF)

    let missingName = "__figdraw_missing_font_for_embedded_fallback__.ttf"
    let id = loadTypeface(missingName, ["test-ubuntu.ttf"])
    check id.int != 0
    check typefaceTable[id].filePath == "test-ubuntu.ttf"
