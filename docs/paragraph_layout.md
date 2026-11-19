# Paragraph Layout

FigDraw lays out wrapped text in a backend-neutral pass over shaped glyphs. A
`ParagraphStyle` on `FontStyle` controls indents, alignment, justification,
hyphenation, and spacing. As with AppKit's paragraph style attribute, the style
of a paragraph's first span applies to the whole paragraph and styles on later
spans are ignored; empty paragraphs use the style of their line break.

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
| `overflowWrap` | `owNormal` lets a word with no shaping-safe break overflow; `owAnywhere` breaks it at any cluster boundary. |
| `hyphenate` | Break overflowing words at registered hyphenation points. |
| `lineSpacing` | Extra space after each line. |
| `spacingBefore`, `spacingAfter` | Space between paragraphs, not applied above the first or below the last. |

Leading and trailing edges follow the paragraph direction, so indents mirror
for right-to-left paragraphs. Indents wider than the box leave an empty measure
rather than overlapping glyphs.

## Line breaking

Lines break after spaces, hyphens, dashes, slashes, and between adjacent CJK
characters, only at shaping-safe cluster boundaries. Spaces where a line wraps
hang past the measure instead of starting the next line, and alignment ignores
them. A word longer than the measure breaks at the last shaping-safe cluster
boundary. When shaping marks none safe, for example between kerned glyphs, the
word overflows unless `overflowWrap` is `owAnywhere`, which breaks it at any
cluster boundary; glyphs beside that break keep the shaping they had while
joined.

Lines are broken in reading order. Bidirectional paragraphs break in source
order, so a right-to-left paragraph's first line holds its first words and uses
the first-line measure; glyphs keep the paragraph's display order within each
line.

`plbOptimal` chooses breaks for the whole paragraph, minimizing uneven word
spacing as TeX does. Spaces may stretch by half and shrink by a third of their
width. The last line keeps its natural spacing, so it must fit without
shrinking unless `lastLineAlign` is `paJustify`. Hyphenated breaks, consecutive hyphenated lines, and very loose lines
next to tight ones carry extra cost. Breaking first tries without pattern
hyphenation, then with it, then with a looser tolerance, and finally falls back
to greedy breaking when no set of breaks fits.

Justified lines widen their interior spaces so the content meets both edges;
the last line follows `lastLineAlign`. Leading spaces keep their width and
hanging spaces stay past the trailing edge. A line without interior spaces keeps
its natural spacing.

## Hyphenation

Soft hyphens (U+00AD) are invisible until a line breaks there, when a hyphen
appears in the preceding glyph's font with its underline and strikethrough. A
soft hyphen is used only if the line fits with its hyphen; when the font has no
hyphen glyph it is a plain break. They work with every style while text wraps.

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
`.hyp.txt` for exceptions), TeX `\patterns{}` / `\hyphenation{}` files (other
TeX commands are ignored), and LibreOffice/Hunspell `.dic` dictionaries in UTF-8
or ISO8859-1. A leading byte-order mark is ignored, and malformed
`LEFTHYPHENMIN`/`RIGHTHYPHENMIN` directives keep the defaults.
`registerHyphenationDirectory` registers `hyph-<lang>.pat.txt`,
`hyph-<lang>.tex`, and `hyph_<lang>.dic` files by language. Check each pattern
set's license before redistributing it.

Layout uses the span font's `language`. Lookup tries the exact tag, its primary
subtag, the first registered regional variant of that subtag, and then patterns
registered for the empty language. Words keep at least `leftMin` and `rightMin`
letters (2 and 3 by default; dictionaries may override them). Leading and
trailing punctuation is excluded and words with other non-letters are not
hyphenated. Inserted hyphens share the source range of the glyph before them,
so selection and hit testing treat them as part of that character; the caret
at the break sits after the hyphen or at the start of the next line.

The registry is process-wide and thread-safe; patterns are immutable once
registered. Each layout resolves patterns once per language.

## Backends

The HarfBuzzy backend always lays out wrapped text with this pass. The Pixie
backend uses it when any span has a paragraph style or a soft hyphen, and
otherwise keeps Pixie's own wrapping; Pixie has no bidirectional shaping. The
UIRelays backend ignores paragraph styles and soft hyphens.

## Future work

- Reshape the two fragments at an `owAnywhere` break. Glyphs beside the break
  currently keep the shaping they had while joined, such as kerning or Arabic
  joining forms. Fixing this needs a backend hook that reshapes a source range,
  including font fallback and bidi analysis.

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
| wrap | 31 ms | 103 ms |
| indents | 32 ms | 107 ms |
| justify, greedy | 33 ms | 107 ms |
| justify, greedy + hyphenate | 39 ms | 116 ms |
| justify, optimal | 36 ms | 112 ms |
| justify, optimal + hyphenate | 44 ms | 121 ms |

A 108 KiB paragraph without break opportunities wraps with `owAnywhere` in
36 ms (HarfBuzzy) and about 110 ms (Pixie), so emergency breaking stays linear.

Before this layout pass, HarfBuzzy took about 8.6 s for the prose document:
glyph source mapping and cluster lookups were quadratic in paragraph length.
