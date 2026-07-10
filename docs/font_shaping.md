# Font Shaping

FigDraw text layout is glyph-id-first. `fontId + glyphId` is the render and
cache identity; source runes remain available for compatibility, diagnostics,
selection, and hit testing.

Harfbuzzy is an optional shaping backend. FigDraw owns the public data model,
backend selection, layout conversion, source mapping, wrapping policy, caret
helpers, and raster dispatch. Harfbuzzy stays behind FigDraw adapters.

## Backend Modes

`figdrawTextBackend` is a compile-time string define:

```nim
const figdrawTextBackend* {.strdefine.} = "pixie"
```

Supported modes:

- `pixie`: Default Pixie layout and Pixie rasterization. Glyph ids are stable
  synthetic ids derived from source runes.
- `hybrid`: Harfbuzzy layout converted to FigDraw arrangements while rendering
  through Pixie-compatible rune rasterization where possible. This is useful for
  diagnostics, but is not a complex-script rendering target.
- `harfbuzzy`: Harfbuzzy shaping and FigDraw's glyph-id raster provider.

`fontutils.typeset` remains the public entry point and delegates to the selected
backend.

## Modules

- `common/fonttypes.nim`: Backend-neutral public data types and source mapping
  helpers.
- `common/typefaces.nim`: Font loading, font ids, static registry, and backend
  dispatch.
- `common/textbackends/pixie.nim`: Pixie layout backend.
- `common/textbackends/harfbuzzy.nim`: Harfbuzzy shaping adapter.
- `common/textrasters/pixie_raster.nim`: Pixie compatibility raster provider.
- `common/textrasters/glyphid_raster.nim`: Glyph-id raster provider using
  HarfBuzz draw callbacks and Pixie path filling.
- `common/fontglyphs.nim`: Glyph iteration, glyph cache keys, and raster
  dispatch.

## Public Data

`GlyphArrangement.arrangedGlyphs` is the canonical placement data. The legacy
parallel arrays `runes`, `positions`, and `selectionRects` remain populated for
current callers.

Important fields:

- `FontGlyphId`: Font-scoped glyph id. In Harfbuzzy mode this is the HarfBuzz
  glyph codepoint. In Pixie mode it is synthetic.
- `GlyphSourceRange`: Half-open byte and rune source ranges for a shaped glyph.
- `ArrangedGlyph.rune`: Cheap representative source rune. This is useful for
  compatibility and debugging, but callers must not treat it as a one-to-one
  source mapping.
- `GlyphArrangement.sourceRunes`: Decoded source text for range-aware callers.

`FigFont` carries shaping controls in backend-neutral terms:

- `fallbackTypefaceIds`: Ordered fallback typeface ids. Harfbuzzy shaping tries
  the primary typeface first, then fallbacks for unsupported shaped runs.
- `features`: OpenType feature settings such as `fontFeature("liga", 0)` or
  `fontFeature("kern")`.
- `variations`: OpenType variable-axis coordinates such as
  `fontVariation("wght", 650.0'f32)`.

These fields remain part of layout hashing. Raster font ids are narrower: they
use the resolved typeface, size, case transform, variable coordinates, and UI
scale. The shaped glyph id distinguishes feature-dependent output without
duplicating raster images for fallback chains, decoration, or line-height
changes.

`GlyphPosition`, yielded by `glyphs(arrangement)`, mirrors the glyph-id-first
shape used by render code:

```nim
type
  GlyphPosition* = ref object
    fontId*: FontId
    glyphId*: FontGlyphId
    cluster*: uint32
    source*: GlyphSourceRange
    rune*: Rune
    isWhitespace*: bool
    pos*: Vec2
    imageOffset*: Vec2
    rect*: Rect
    descent*: float32
    lineHeight*: float32
    fill*: Fill
```

Rendering uses `glyph.glyphId` for cache identity and keeps `glyph.rune` for
cheap whitespace checks and human-readable diagnostics.

## Source Mapping

Use source helpers instead of assuming one visual glyph equals one source rune.
Ligatures, combining marks, and mixed-direction visual runs can map one source
range to multiple glyphs, or multiple source runes to one glyph.

Cheap glyph-to-source helpers:

```nim
func sourceRune*(arrangement: GlyphArrangement, glyphIndex: int): Rune
func sourceRuneRange*(arrangement: GlyphArrangement, glyphIndex: int): Slice[int]
iterator sourceRunes*(arrangement: GlyphArrangement, glyphIndex: int): Rune
```

Range selection and hit testing helpers:

```nim
func glyphRangeFor*(
  arrangement: GlyphArrangement, sourceRange: Slice[int]
): Slice[int]

func glyphRangeForRawBytes*(
  arrangement: GlyphArrangement, byteRange: Slice[int]
): Slice[int]

func glyphSelectionRectsFor*(
  arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect]

func glyphSelectionRectsForRawBytes*(
  arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect]

func selectionBandsFor*(
  arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect]

func selectionBandsForRawBytes*(
  arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect]

func selectionRectsFor*(
  arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect]

func selectionRectsForRawBytes*(
  arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect]

func glyphIndexAt*(arrangement: GlyphArrangement, point: Vec2): int
func sourceRuneRangeAt*(arrangement: GlyphArrangement, point: Vec2): Slice[int]
```

`selectionRectsFor` returns merged visual selection bands for source-rune ranges.
It groups selected glyphs by visual line fragment and uses the full line height
for each band, which avoids shaped glyph boxes producing uneven or overlapping
selection paint. Use `glyphSelectionRectsFor` when a caller needs the raw glyph
rectangles for diagnostics or fine-grained hit-test checks. The `RawBytes`
variants are for lower-level callers that already have byte offsets.

Caret helpers expose source insertion indices instead of glyph indices:

```nim
type
  TextCaretAffinity* = enum
    CaretLeading
    CaretInside
    CaretTrailing

  TextCaretPosition* = object
    sourceRune*: int
    glyphIndex*: int
    lineIndex*: int
    affinity*: TextCaretAffinity
    pos*: Vec2
    rect*: Rect

func caretPositionsFor*(
  arrangement: GlyphArrangement, sourceRune: int
): seq[TextCaretPosition]

func nearestSourceRuneForCaretPoint*(
  arrangement: GlyphArrangement, point: Vec2
): int
```

`caretPositionsFor` can return more than one visual caret rectangle at
bidi boundaries. `nearestSourceRuneForCaretPoint` performs the inverse query for
local hit testing.

## Harfbuzzy Layout

The Harfbuzzy adapter converts shaped runs into FigDraw data:

- `glyph.codepoint` becomes `FontGlyphId`.
- `glyph.cluster` is retained for source mapping and break logic.
- The adapter shapes through a Harfbuzzy `ShapeContext` built from the primary
  typeface plus `FigFont.fallbackTypefaceIds`.
- Adjacent spans with the same shaping font are shaped together even when their
  fills differ, preserving contextual shaping across paint-only boundaries.
- OpenType features from `FigFont.features` are passed to paragraph shaping.
- Variable axes from `FigFont.variations` are applied to each Harfbuzzy font
  before shaping.
- A single styled input span can become multiple FigDraw spans when fallback
  picks different typefaces. Each emitted span keeps the input fill and stores
  the actual shaped `fontId` used by its glyph run.
- HarfBuzz glyph flags are consumed inside the adapter so preferred wrapping can
  respect unsafe-to-break metadata without exposing HarfBuzz-specific flags.
- Source byte and rune ranges are stored in `GlyphSourceRange`.
- Advances and offsets are scaled by `font.size / face.upem`.
- `imageOffset` comes from glyph extents so raster images can include negative
  bearings while baseline placement stays stable.

The backend wraps greedily over shaped glyphs. It prefers whitespace clusters
when the next shaped glyph is safe to break before, recognizes soft hyphen,
zero-width space, hyphen-like separators, and common CJK/Kana/Hangul adjacent
break opportunities, and otherwise uses only safe cluster boundaries. A cluster
without a safe boundary is allowed to overflow instead of being split without
reshaping.

Line slices are aligned after wrapping. Vertical alignment is applied to the
whole arrangement. When `minContent` is enabled, Harfbuzzy expands the alignment
height to the wrapped content height before vertical alignment so bottom- or
middle-aligned text does not shift above the layout bounds.

## Rendering

Glyph cache identity is glyph-id-based:

```nim
proc hash*(glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0): Hash =
  hash((2344, glyph.fontId, glyph.glyphId, lcdFiltering, subpixelVariant))
```

Raster dispatch follows the selected backend:

- `harfbuzzy` renders by `fontId + glyphId` through the glyph-id raster
  provider. Variable axes stored on the resolved `FigFont` are applied before
  drawing glyph outlines.
- `pixie` and `hybrid` render through Pixie's rune raster path.

Selection and hit testing use source ranges, not glyph ids.

The glyph-id raster provider requires HarfBuzz 7.0 or newer. It currently
extracts monochrome outlines; color bitmap, SVG, and COLR paint data require a
separate color-font raster path.

## Regression Coverage

The test suite covers:

- Shaped glyph ids and source ranges.
- Ligature source mapping and source-rune iteration.
- Wrapping at shaped glyph boundaries.
- Preserving ligature ranges on one line.
- Preserving shaping across paint-only span boundaries.
- Consecutive hard breaks and zero-width line placeholders.
- Original source mapping after font-case transforms.
- `noKerningAdjustments` translation to the OpenType `kern` feature.
- CJK wrapping without whitespace using the dependency test font.
- Combining marks and Hebrew marks through source-range selection and hit
  testing.
- Mixed LTR/RTL source-range hit testing and caret-position helpers.
- Font fallback preserving fallback `fontId` on shaped runs.
- OpenType feature control for ligature shaping.
- Variable axes carrying through shaped font ids.
- Arabic shaping when a suitable named system Arabic font is available.
- Pure Harfbuzzy glyph-id rasterization.

## Future Extensions

- Full Unicode Line Breaking Algorithm tailoring for locale-specific wrapping.
- Widget-level editing policy, including arrow-key behavior, selection
  extension, and IME integration.
