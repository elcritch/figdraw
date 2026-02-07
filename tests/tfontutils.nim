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
    let typefaceId = loadTypeface("Ubuntu.ttf", fontData, TTF)
    let uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    setFigUiScale 1.0

    let a = "A".runeAt(0)
    let b = "B".runeAt(0)
    let positions = [(a, vec2(12, 16)), (b, vec2(40, 16))]

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
