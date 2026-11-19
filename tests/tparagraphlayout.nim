import std/[math, os, strutils, unicode, unittest]

import figdraw
import figdraw/common/hyphenation

const
  Prose =
    "Typesetting balances the measure against word spacing so that every " &
    "line reads evenly and the paragraph keeps a steady texture from top to " &
    "bottom without rivers of white space running through the column."
  LiangPatterns = "hy3ph he2n hena4 hen5at 1na n2at 1tio 2io o2n"

proc testFont(size = 18.0'f32): FigFont =
  let typefaceId =
    loadTypeface("Ubuntu.ttf", readFile(figDataDir() / "Ubuntu.ttf"), TTF)
  FigFont(typefaceId: typefaceId, size: size, language: "en")

proc layout(
    text: string,
    paragraph: ParagraphStyle,
    width = 260.0'f32,
    hAlign = FontHorizontal.Left,
    wrap = true,
): GlyphArrangement =
  typesetForMeasurement(
    rect(0, 0, width, 2000),
    [(fs(testFont(), fill(rgba(0, 0, 0, 255)), paragraph), text)],
    hAlign,
    Top,
    minContent = false,
    wrap = wrap,
  )

proc lineText(arrangement: GlyphArrangement, line: Slice[int]): string =
  for index in line:
    let rune = arrangement.arrangedGlyphs[index].rune
    if rune.int != 0:
      result.add rune

proc contentBounds(arrangement: GlyphArrangement, line: Slice[int]): Rect =
  var
    first = float32.high
    last = -float32.high
    top = float32.high
  for index in line:
    let glyph = arrangement.arrangedGlyphs[index]
    top = min(top, glyph.rect.y)
    if not glyph.isWhitespace:
      first = min(first, glyph.rect.x)
      last = max(last, glyph.rect.x + glyph.rect.w)
  rect(first, top, last - first, 0)

proc backends(): seq[TextBackendKind] =
  for backend in [TextBackendKind.Harfbuzzy, TextBackendKind.Pixie]:
    if textBackendAvailable(backend):
      result.add backend

for backend in backends():
  setTextBackend(backend)
  suite "paragraph layout (" & $backend & ")":
    setup:
      clearHyphenationPatterns()

    test "default paragraph styles leave layout unchanged":
      let
        plain = typesetForMeasurement(
          rect(0, 0, 260, 2000),
          [(fs(testFont()), Prose)],
          Left,
          Top,
          minContent = false,
          wrap = true,
        )
        styled = layout(Prose, ParagraphStyle())
      check plain.lines == styled.lines
      check plain.positions == styled.positions
      check getContentHash(vec2(260, 2000), [(fs(testFont()), Prose)]) ==
        getContentHash(
          vec2(260, 2000),
          [(fs(testFont(), fill(rgba(0, 0, 0, 255)), ParagraphStyle()), Prose)],
        )
      check getContentHash(vec2(260, 2000), [(fs(testFont()), Prose)]) !=
        getContentHash(
          vec2(260, 2000),
          [
            (
              fs(testFont(), fill(rgba(0, 0, 0, 255)), ParagraphStyle(headIndent: 8)),
              Prose,
            )
          ],
        )

    test "first-line, hanging, and tail indents shape each line's measure":
      let
        style = ParagraphStyle(firstLineIndent: 30, headIndent: 12, tailIndent: 20)
        indented = layout(Prose, style)
        plain = layout(Prose, ParagraphStyle())
      require indented.lines.len > 2
      check indented.lines.len >= plain.lines.len
      for lineIndex, line in indented.lines:
        let bounds = indented.contentBounds(line)
        let lead = if lineIndex == 0: style.firstLineIndent else: style.headIndent
        check abs(bounds.x - lead) < 0.5
        check bounds.x + bounds.w <= 260 - style.tailIndent + 0.5

    test "unwrapped text keeps a first-line indent":
      let arrangement =
        layout("short line", ParagraphStyle(firstLineIndent: 16), wrap = false)
      check abs(arrangement.contentBounds(arrangement.lines[0]).x - 16) < 0.5

    test "centered and right-aligned lines stay between the indents":
      for (align, expected) in [(paCenter, 0), (paRight, 1)]:
        let
          style = ParagraphStyle(
            headIndent: 40, firstLineIndent: 40, tailIndent: 10, align: align
          )
          arrangement = layout("centered words", style)
          bounds = arrangement.contentBounds(arrangement.lines[0])
        if expected == 0:
          check abs((bounds.x + bounds.w / 2) - (40 + (260 - 40 - 10) / 2)) < 1.0
        else:
          check abs(bounds.x + bounds.w - (260 - 10)) < 0.5

    test "justified lines fill the measure except the last":
      for breaking in [plbGreedy, plbOptimal]:
        let
          style = ParagraphStyle(
            align: paJustify, lineBreaking: breaking, headIndent: 6, tailIndent: 4
          )
          arrangement = layout(Prose, style)
        require arrangement.lines.len > 2
        for lineIndex, line in arrangement.lines:
          let bounds = arrangement.contentBounds(line)
          check abs(bounds.x - (if lineIndex == 0: 0.0'f32 else: 6.0'f32)) < 0.5
          if lineIndex < arrangement.lines.high:
            check abs(bounds.x + bounds.w - (260 - 4)) < 0.75
          else:
            check bounds.x + bounds.w < 255.0

    test "optimal breaking has no more spacing demerits than greedy breaking":
      # Recompute Knuth-Plass demerits from the output: each justified line's
      # stretch ratio follows from its widened spaces and the natural space.
      let naturalSpace = block:
        let ragged = layout("a b", ParagraphStyle(), 1000)
        var width = 0.0'f32
        for glyph in ragged.arrangedGlyphs:
          if glyph.isWhitespace and glyph.rect.w > 0:
            width = glyph.rect.w
        width

      proc demerits(arrangement: GlyphArrangement): float =
        var previousFitness = 1
        for lineIndex, line in arrangement.lines:
          var
            spaces = 0
            spaceWidth = 0.0
          if lineIndex < arrangement.lines.high:
            let content = block:
              var range = line
              while arrangement.arrangedGlyphs[range.b].isWhitespace:
                dec range.b
              range
            for index in content:
              let glyph = arrangement.arrangedGlyphs[index]
              if glyph.isWhitespace and glyph.rect.w > 0:
                inc spaces
                spaceWidth += glyph.rect.w
          let
            ratio =
              if spaces > 0:
                let extra = spaceWidth / spaces.float - naturalSpace
                # Spaces stretch by half and shrink by a third of their width.
                extra / (naturalSpace * (if extra < 0: 1.0 / 3.0 else: 0.5))
              else:
                0.0
            badness = min(100.0 * pow(abs(ratio), 3.0), 10000.0)
            fitness =
              if ratio < -0.5:
                0
              elif ratio <= 0.5:
                1
              elif ratio <= 1.0:
                2
              else:
                3
          result += pow(10.0 + badness, 2.0)
          if abs(fitness - previousFitness) > 1:
            result += 10000.0
          previousFitness = fitness

      require naturalSpace > 0
      for width in [180.0'f32, 230, 300]:
        let
          text = Prose & " " & Prose
          greedy = layout(text, ParagraphStyle(align: paJustify), width)
          optimal = layout(
            text, ParagraphStyle(align: paJustify, lineBreaking: plbOptimal), width
          )
        check optimal.demerits() <= greedy.demerits() * 1.0001

    test "soft hyphens show a hyphen only where a line breaks":
      let
        word = "extra­ordinarily­long­compound"
        narrow = layout(word & " ends", ParagraphStyle(), 120)
        wide = layout(word & " ends", ParagraphStyle(), 1000)
      check "-" notin wide.lineText(wide.lines[0])
      require narrow.lines.len > 1
      check narrow.lineText(narrow.lines[0]).endsWith("-")
      for line in narrow.lines:
        check narrow.contentBounds(line).x + narrow.contentBounds(line).w <= 120.5

    test "registered patterns hyphenate overflowing words":
      registerHyphenationPatterns("en", parseTexHyphenationPatterns(LiangPatterns))
      let
        style = ParagraphStyle(hyphenate: true)
        arrangement = layout("a hyphenation", style, 70)
        unhyphenated = layout("a hyphenation", ParagraphStyle(), 70)
      require arrangement.lines.len > 1
      let first = arrangement.lineText(arrangement.lines[0])
      check first.endsWith("-")
      check first.strip(chars = {'-'}).endsWith("hy") or first.endsWith("hyphen-")
      for line in unhyphenated.lines:
        check not unhyphenated.lineText(line).endsWith("-")
      var visible: string
      for line in arrangement.lines:
        visible.add arrangement.lineText(line).replace("-", "").replace(" ", "")
      check visible == "ahyphenation"
      for index, glyph in arrangement.arrangedGlyphs:
        if glyph.rune == Rune('-'):
          check glyph.source == arrangement.arrangedGlyphs[index - 1].source
      check arrangement.runes.len == arrangement.arrangedGlyphs.len
      var spanned = 0
      for span in arrangement.spans:
        spanned += span.len
      check spanned == arrangement.arrangedGlyphs.len

    test "line and paragraph spacing separate stacked lines":
      let
        base = layout("one\ntwo\nthree", ParagraphStyle())
        spaced = layout(
          "one\ntwo\nthree",
          ParagraphStyle(lineSpacing: 4, spacingBefore: 3, spacingAfter: 5),
        )
        wrapped = layout(Prose, ParagraphStyle(lineSpacing: 7))
        plain = layout(Prose, ParagraphStyle())
      require base.lines.len == 3
      require spaced.lines.len == 3
      for lineIndex in 1 .. 2:
        let
          basePitch =
            base.contentBounds(base.lines[lineIndex]).y -
            base.contentBounds(base.lines[lineIndex - 1]).y
          spacedPitch =
            spaced.contentBounds(spaced.lines[lineIndex]).y -
            spaced.contentBounds(spaced.lines[lineIndex - 1]).y
        check abs(spacedPitch - basePitch - (4 + 5 + 3)) < 0.01
      check abs(
        (
          wrapped.contentBounds(wrapped.lines[1]).y -
          wrapped.contentBounds(wrapped.lines[0]).y
        ) - (
          plain.contentBounds(plain.lines[1]).y - plain.contentBounds(plain.lines[0]).y
        ) - 7
      ) < 0.01

    test "paragraph styles follow the first span of each paragraph":
      let
        font = testFont()
        quote = ParagraphStyle(firstLineIndent: 24, headIndent: 24)
        arrangement = typesetForMeasurement(
          rect(0, 0, 400, 400),
          [
            (fs(font), "plain\n"),
            (fs(font, fill(rgba(0, 0, 0, 255)), quote), "quoted"),
            (fs(font), " tail\nafter"),
          ],
          Left,
          Top,
          minContent = false,
          wrap = true,
        )
      require arrangement.lines.len == 3
      check abs(arrangement.contentBounds(arrangement.lines[0]).x) < 0.5
      check abs(arrangement.contentBounds(arrangement.lines[1]).x - 24) < 0.5
      check abs(arrangement.contentBounds(arrangement.lines[2]).x) < 0.5

    test "right-aligned wrapped lines keep hanging spaces outside the box":
      let arrangement = layout(
        "abc" & " ".repeat(30) & "def ghi", ParagraphStyle(), 100, hAlign = Right
      )
      for line in arrangement.lines:
        let bounds = arrangement.contentBounds(line)
        check bounds.x >= -0.01
        check bounds.x + bounds.w <= 100.01

    test "a rejected soft hyphen is not reused as an invisible break":
      let
        prefix = "abcdefghij"
        prefixWidth = block:
          let measured = layout(prefix, ParagraphStyle(), 1000, wrap = false)
          measured.contentBounds(measured.lines[0]).w
        arrangement =
          layout(prefix & "\u00ADklmnopqrs", ParagraphStyle(), prefixWidth + 1)
      for line in arrangement.lines:
        let last = arrangement.arrangedGlyphs[line.b]
        if last.source.runeEnd - last.source.runeStart == 1 and
            arrangement.sourceRunes[last.source.runeStart] == Rune(0x00AD):
          check last.rune == Rune('-')

    test "optimal breaking keeps an unjustified last line within the measure":
      let
        text = "aaaa bbbb"
        natural = block:
          let measured = layout(text, ParagraphStyle(), 1000, wrap = false)
          measured.contentBounds(measured.lines[0]).w
        measure = natural - 1
        arrangement = layout(
          text, ParagraphStyle(align: paJustify, lineBreaking: plbOptimal), measure
        )
      check arrangement.lines.len == 2
      for line in arrangement.lines:
        let bounds = arrangement.contentBounds(line)
        check bounds.x + bounds.w <= measure + 0.01

    test "indents wider than the box never overlap glyphs":
      for style in [
        ParagraphStyle(firstLineIndent: 500, headIndent: 500, align: paJustify),
        ParagraphStyle(headIndent: 150, tailIndent: 150, align: paCenter),
      ]:
        let arrangement = layout(Prose, style, 200)
        for line in arrangement.lines:
          var previousRight = -float32.high
          for index in line:
            let glyph = arrangement.arrangedGlyphs[index]
            check glyph.rect.x >= previousRight - 0.01
            previousRight = glyph.rect.x + glyph.rect.w

    test "justified lines keep leading spaces inside the measure":
      let arrangement = layout("   " & Prose, ParagraphStyle(align: paJustify))
      require arrangement.lines.len > 1
      check arrangement.arrangedGlyphs[arrangement.lines[0].a].rect.x >= -0.01
      let bounds = arrangement.contentBounds(arrangement.lines[0])
      check bounds.x + bounds.w <= 260.5

    test "overflow wrap breaks shaping-unsafe words only when asked":
      # HarfBuzz marks every boundary between kerned "x" glyphs unsafe.
      let word = "x".repeat(60)
      let anywhere = layout(word, ParagraphStyle(overflowWrap: owAnywhere), 200)
      check anywhere.lines.len > 1
      for line in anywhere.lines:
        let bounds = anywhere.contentBounds(line)
        check bounds.x + bounds.w <= 200.5
      if backend == TextBackendKind.Harfbuzzy:
        let normal = layout(word, ParagraphStyle(), 200)
        check normal.lines.len == 1

    test "long unbroken text wraps every line within the measure":
      let
        word = "x".repeat(20_000)
        arrangement =
          layout(word, ParagraphStyle(hyphenate: true, overflowWrap: owAnywhere), 200)
      require arrangement.lines.len > 100
      var glyphs = 0
      for line in arrangement.lines:
        glyphs += line.len
        let bounds = arrangement.contentBounds(line)
        check bounds.x + bounds.w <= 200.5
      check glyphs == 20_000

    test "paragraph styles follow source offsets past dropped controls":
      let
        font = testFont()
        quote = ParagraphStyle(firstLineIndent: 24, headIndent: 24)
        arrangement = typesetForMeasurement(
          rect(0, 0, 400, 400),
          [
            (fs(font), "Intro\r\n"),
            (fs(font, fill(rgba(0, 0, 0, 255)), quote), "quoted\ttext"),
            (fs(font), "\r\nAfter"),
          ],
          Left,
          Top,
          minContent = false,
          wrap = true,
        )
      require arrangement.lines.len == 3
      check abs(arrangement.contentBounds(arrangement.lines[0]).x) < 0.5
      check abs(arrangement.contentBounds(arrangement.lines[1]).x - 24) < 0.5
      check abs(arrangement.contentBounds(arrangement.lines[2]).x) < 0.5

    test "styled paragraphs align vertically with min content":
      let
        font = testFont()
        box = rect(0, 0, 260, 600)
        arrangement = typesetForMeasurement(
          box,
          [(fs(font, fill(rgba(0, 0, 0, 255)), ParagraphStyle(headIndent: 10)), Prose)],
          Left,
          Middle,
          minContent = true,
          wrap = true,
        )
        bounds = arrangement.bounding
      check abs((bounds.y + bounds.h / 2) - box.h / 2) < 1.0

    test "unwrapped centered text centers between the indents":
      let
        style = ParagraphStyle(firstLineIndent: 40, tailIndent: 20, align: paCenter)
        arrangement = layout("short", style, 300, wrap = false)
        bounds = arrangement.contentBounds(arrangement.lines[0])
      check abs((bounds.x + bounds.w / 2) - (40 + (300 - 40 - 20) / 2)) < 0.5

    test "carets around an inserted hyphen stay on their lines":
      registerHyphenationPatterns("en", parseTexHyphenationPatterns(LiangPatterns))
      let arrangement = layout("a hyphenation", ParagraphStyle(hyphenate: true), 70)
      require arrangement.lines.len > 1
      var hyphenIndex = -1
      for index, glyph in arrangement.arrangedGlyphs:
        if glyph.rune == Rune('-'):
          hyphenIndex = index
          break
      require hyphenIndex > 0
      let
        breakRune = arrangement.arrangedGlyphs[hyphenIndex].source.runeEnd
        carets = arrangement.caretPositionsFor(breakRune)
        hyphenRect = arrangement.arrangedGlyphs[hyphenIndex].rect
      check carets.len == 2
      var lines: seq[int]
      for caret in carets:
        lines.add caret.lineIndex
      check 0 in lines
      check 1 in lines
      for caret in carets:
        if caret.lineIndex == 0:
          check abs(caret.pos.x - (hyphenRect.x + hyphenRect.w)) < 0.01
      for rune in 0 .. arrangement.sourceRunes.len:
        check arrangement.caretPositionsFor(rune).len > 0
      check arrangement.nearestSourceRuneForCaretPoint(
        vec2(hyphenRect.x + hyphenRect.w / 2, hyphenRect.y + hyphenRect.h / 2)
      ) in [breakRune - 1, breakRune]

if textBackendAvailable(TextBackendKind.Harfbuzzy):
  setTextBackend(TextBackendKind.Harfbuzzy)
  suite "right-to-left paragraph layout":
    proc hebrew(): FigFont =
      let path =
        currentSourcePath().parentDir.parentDir / "examples" / "fonts" /
        "NotoSansHebrew-wdth-wght.ttf"
      let typefaceId = loadTypeface("NotoSansHebrew", readFile(path), TTF)
      FigFont(typefaceId: typefaceId, size: 18, language: "he")

    const Words =
      "שלום עולם זהו טקסט ארוך מאוד שנשבר לשורות רבות בפסקה אחת"

    proc layoutHebrew(style: ParagraphStyle, width: float32): GlyphArrangement =
      typesetForMeasurement(
        rect(0, 0, width, 2000),
        [(fs(hebrew(), fill(rgba(0, 0, 0, 255)), style), Words & " " & Words)],
        Left,
        Top,
        minContent = false,
        wrap = true,
      )

    test "lines break from the logical start with each line's own measure":
      let
        style = ParagraphStyle(firstLineIndent: 60, align: paJustify)
        arrangement = layoutHebrew(style, 300)
      require arrangement.lines.len > 2
      var previousStart = -1
      for lineIndex, line in arrangement.lines:
        var start = high(int)
        for index in line:
          start = min(start, arrangement.arrangedGlyphs[index].source.runeStart)
        check start > previousStart
        previousStart = start
        let
          bounds = arrangement.contentBounds(line)
          lead = if lineIndex == 0: 60.0'f32 else: 0.0'f32
        check bounds.x >= -0.5
        check bounds.x + bounds.w <= 300 - lead + 0.5
        if lineIndex < arrangement.lines.high:
          check abs(bounds.x) < 0.75
          check abs(bounds.x + bounds.w - (300 - lead)) < 0.75
      let last = arrangement.contentBounds(arrangement.lines[^1])
      check abs(last.x + last.w - 300) < 0.75

    test "the first line holds the paragraph's first words":
      let arrangement = layoutHebrew(ParagraphStyle(), 300)
      require arrangement.lines.len > 1
      var firstLineRunes: seq[int]
      for index in arrangement.lines[0]:
        firstLineRunes.add arrangement.arrangedGlyphs[index].source.runeStart
      check 0 in firstLineRunes
