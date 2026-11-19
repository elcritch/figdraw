# Paragraph Layout

FigDraw lays out wrapped text in a backend-neutral pass over shaped glyphs. A
`ParagraphStyle` on `FontStyle` controls indents, alignment, justification,
hyphenation, and spacing. The style of a paragraph's first span applies to the
whole paragraph; empty paragraphs use the style of their line break.

```nim
let body = fs(
  font,
  fill(rgba(30, 34, 40, 255)),
  ParagraphStyle(
    firstLineIndent: 24,
    headIndent: 0,
    align: paJustify,
    lineBreaking: plbOptimal,
    hyphenate: true,
    spacingAfter: 8,
  ),
)
let layout = typeset(rect(0, 0, 480, 800), [(body, text)], minContent = false, wrap = true)
```

The default `ParagraphStyle()` leaves layout and content hashes unchanged.

## Fields

| Field | Effect |
| --- | --- |
| `firstLineIndent` | Leading inset of a paragraph's first line, in pixels. |
| `headIndent` | Leading inset of the following lines (hanging indent when smaller than `firstLineIndent`). |
| `tailIndent` | Trailing inset of every line. |
| `align` | `paInherit` uses the typeset call's `hAlign`; `paLeft`, `paCenter`, `paRight`, or `paJustify`. |
| `lastLineAlign` | Last line of a justified paragraph: `paInherit` uses the paragraph's leading edge; `paJustify` stretches it too. |
| `lineBreaking` | `plbGreedy` fills lines in turn; `plbOptimal` uses Knuth–Plass for justified paragraphs. |
| `hyphenate` | Break overflowing words at registered hyphenation points. |
| `lineSpacing` | Extra space after each line. |
| `spacingBefore`, `spacingAfter` | Space between paragraphs, not applied above the first or below the last. |

Leading and trailing edges follow the paragraph direction, so indents mirror
for right-to-left paragraphs. Right-to-left paragraphs break every line with
the `headIndent` measure.

## Line breaking

Lines break after spaces, hyphens, dashes, slashes, and between CJK
characters, only at shaping-safe cluster boundaries. Trailing spaces hang past
the measure instead of starting the next line. A word longer than the measure
breaks at the last safe cluster boundary.

`plbOptimal` chooses breaks for the whole paragraph, minimizing uneven word
spacing as TeX does. Spaces may stretch by half and shrink by a third of their
width. Hyphenated breaks, consecutive hyphenated lines, and very loose lines
next to tight ones carry extra cost. Breaking first tries without pattern
hyphenation, then with it, then with a looser tolerance, and finally falls back
to greedy breaking when no set of breaks fits.

Justified lines widen their interior spaces so the content meets both edges;
the last line follows `lastLineAlign`. A line without interior spaces keeps its
natural spacing.

## Hyphenation

Soft hyphens (U+00AD) are invisible until a line breaks there, when a hyphen
appears in the preceding glyph's font. They work with every style while text
wraps.

Automatic hyphenation uses Liang patterns, the same data TeX uses. FigDraw
ships no language data; register patterns at startup, for example from an
application asset folder:

```nim
import figdraw

discard registerHyphenationDirectory(appAssetDir / "hyphenation")
# or
registerHyphenationPatterns("en-US", loadHyphenationPatterns("hyph-en-us.pat.txt"))
```

`loadHyphenationPatterns` reads hyph-utf8 `.pat.txt` files (with a sibling
`.hyp.txt` for exceptions), TeX `\patterns{}` / `\hyphenation{}` files, and
LibreOffice/Hunspell `.dic` dictionaries in UTF-8 or ISO8859-1.
`registerHyphenationDirectory` registers `hyph-<lang>.pat.txt`,
`hyph-<lang>.tex`, and `hyph_<lang>.dic` files by language. Check each pattern
set's license before redistributing it.

Layout uses the span font's `language`. Lookup tries the exact tag, its primary
subtag, the first registered regional variant of that subtag, and then patterns
registered for the empty language. Words keep at least `leftMin` and `rightMin`
letters (2 and 3 by default; dictionaries may override them). Leading and
trailing punctuation is excluded, words with other non-letters are not
hyphenated, and right-to-left words are never hyphenated. Inserted hyphens
share the source range of the glyph before them, so selection and hit testing
treat them as part of that character.

The registry is process-wide and thread-safe; patterns are immutable once
registered.

## Backends

The HarfBuzzy backend always lays out wrapped text with this pass. The Pixie
backend uses it when any span has a paragraph style or a soft hyphen, and
otherwise keeps Pixie's own wrapping. The UIRelays backend ignores paragraph
styles.

## Performance

`tests/bench_text_layout.nim` measures each mode on both backends:

```sh
nim r -d:release tests/bench_text_layout.nim
FIGDRAW_HYPHEN_PATTERNS=/path/to/hyph_en_US.dic nim r -d:release tests/bench_text_layout.nim
```

On an Apple M-series laptop with a 108 KiB, 200-paragraph document at 420 px
(US English patterns), median times were:

| Mode | HarfBuzzy source spans | Pixie |
| --- | ---: | ---: |
| wrap | 34 ms | 108 ms |
| indents | 35 ms | 113 ms |
| justify, greedy | 35 ms | 112 ms |
| justify, greedy + hyphenate | 38 ms | 116 ms |
| justify, optimal | 40 ms | 117 ms |
| justify, optimal + hyphenate | 45 ms | 121 ms |

Before this layout pass, HarfBuzzy took about 8.6 s for the same document:
glyph source mapping and cluster lookups were quadratic in paragraph length.
