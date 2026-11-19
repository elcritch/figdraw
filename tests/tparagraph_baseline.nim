## Unstyled layout must match FigDraw 0.47 output for text without paragraph
## styles. The fixture was written by running this file against the previous
## release with `-d:figdrawWriteParagraphBaseline`; it only uses APIs that
## existed there. Cases avoid the intended changes: hanging space runs at a
## wrap and trailing spaces in centered or right-aligned wrapped lines.

import std/[json, os, unittest]

import figdraw

const FixturePath =
  currentSourcePath().parentDir / "expected" / "paragraph_baseline.json"

type BaselineCase = object
  name: string
  text: string
  width: float32
  height: float32
  hAlign: FontHorizontal
  vAlign: FontVertical
  minContent: bool
  wrap: bool

proc repeatStr(text: string, count: int): string =
  for _ in 0 ..< count:
    result.add text

proc cases(): seq[BaselineCase] =
  let prose =
    "Typesetting balances the measure against word spacing so that every line " &
    "reads evenly and the paragraph keeps a steady texture."
  for (name, text, width, hAlign, vAlign, minContent, wrap) in [
    ("wrapped prose", prose, 260.0'f32, Left, Top, false, true),
    (
      "paragraphs", "first paragraph wraps here\n\nsecond one\nthird", 140.0'f32, Left,
      Top, false, true,
    ),
    ("unwrapped left", "single line", 300.0'f32, Left, Top, false, false),
    ("unwrapped center", "single line", 300.0'f32, Center, Top, false, false),
    ("unwrapped right", "single line", 300.0'f32, Right, Top, false, false),
    (
      "cjk",
      "日本語のテキストを折り返します。日本語のテキストを折り返します。",
      120.0'f32, Left, Top, false, true,
    ),
    ("long word", "a".repeatStr(60) & " tail", 200.0'f32, Left, Top, false, true),
    (
      "hyphen and slash", "state-of-the-art client/server pipelines", 120.0'f32, Left,
      Top, false, true,
    ),
    ("middle min content", prose, 260.0'f32, Left, Middle, true, true),
    ("bottom", "short\ntext", 200.0'f32, Left, Bottom, false, true),
  ]:
    result.add BaselineCase(
      name: name,
      text: text,
      width: width,
      height: 400,
      hAlign: hAlign,
      vAlign: vAlign,
      minContent: minContent,
      wrap: wrap,
    )

proc snapshot(arrangement: GlyphArrangement): JsonNode =
  var lines = newJArray()
  for line in arrangement.lines:
    lines.add %*[line.a, line.b]
  var glyphs = newJArray()
  for glyph in arrangement.arrangedGlyphs:
    glyphs.add %*[glyph.rect.x, glyph.rect.y, glyph.rect.w, glyph.source.runeStart]
  %*{"lines": lines, "glyphs": glyphs}

proc layout(item: BaselineCase): GlyphArrangement =
  let typefaceId =
    loadTypeface("Ubuntu.ttf", readFile(figDataDir() / "Ubuntu.ttf"), TTF)
  typesetForMeasurement(
    rect(0, 0, item.width, item.height),
    [(fs(FigFont(typefaceId: typefaceId, size: 18)), item.text)],
    item.hAlign,
    item.vAlign,
    minContent = item.minContent,
    wrap = item.wrap,
  )

proc backends(): seq[TextBackendKind] =
  for backend in [TextBackendKind.Harfbuzzy, TextBackendKind.Pixie]:
    if textBackendAvailable(backend):
      result.add backend

when defined(figdrawWriteParagraphBaseline):
  var fixture = newJObject()
  for backend in backends():
    setTextBackend(backend)
    for item in cases():
      fixture[$backend & "/" & item.name] = item.layout().snapshot()
  writeFile(FixturePath, fixture.pretty())
  echo "wrote ", FixturePath
else:
  let fixture = parseJson(readFile(FixturePath))
  for backend in backends():
    setTextBackend(backend)
    suite "unstyled layout matches the previous release (" & $backend & ")":
      for item in cases():
        test item.name:
          let key = $backend & "/" & item.name
          require fixture.hasKey(key)
          let
            expected = fixture[key]
            actual = item.layout().snapshot()
          check actual["lines"] == expected["lines"]
          require actual["glyphs"].len == expected["glyphs"].len
          for index in 0 ..< expected["glyphs"].len:
            let
              want = expected["glyphs"][index]
              got = actual["glyphs"][index]
            for field in 0 .. 2:
              check abs(got[field].getFloat() - want[field].getFloat()) < 0.01
            check got[3].getInt() == want[3].getInt()
