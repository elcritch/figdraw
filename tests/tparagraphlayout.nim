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
                (spaceWidth / spaces.float - naturalSpace) / (naturalSpace * 0.5)
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
