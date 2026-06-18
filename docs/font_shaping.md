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
func glyphRangeForSourceRunes*(
  arrangement: GlyphArrangement, sourceRange: Slice[int]
): Slice[int]

func glyphRangeForSourceBytes*(
  arrangement: GlyphArrangement, byteRange: Slice[int]
): Slice[int]

func selectionRectsForSourceRunes*(
  arrangement: GlyphArrangement, sourceRange: Slice[int]
): seq[Rect]

func selectionRectsForSourceBytes*(
  arrangement: GlyphArrangement, byteRange: Slice[int]
): seq[Rect]

func glyphIndexAt*(arrangement: GlyphArrangement, point: Vec2): int
func sourceRuneRangeAt*(arrangement: GlyphArrangement, point: Vec2): Slice[int]
```

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

func caretPositionsForSourceRune*(
  arrangement: GlyphArrangement, sourceRune: int
): seq[TextCaretPosition]

func nearestSourceRuneForCaretPoint*(
  arrangement: GlyphArrangement, point: Vec2
): int
```

`caretPositionsForSourceRune` can return more than one visual caret rectangle at
bidi boundaries. `nearestSourceRuneForCaretPoint` performs the inverse query for
local hit testing.

## Harfbuzzy Layout

The Harfbuzzy adapter converts shaped runs into FigDraw data:

- `glyph.codepoint` becomes `FontGlyphId`.
- `glyph.cluster` is retained for source mapping and break logic.
- HarfBuzz glyph flags are consumed inside the adapter so preferred wrapping can
  respect unsafe-to-break metadata without exposing HarfBuzz-specific flags.
- Source byte and rune ranges are stored in `GlyphSourceRange`.
- Advances and offsets are scaled by `font.size / face.upem`.
- `imageOffset` comes from glyph extents so raster images can include negative
  bearings while baseline placement stays stable.

The backend wraps greedily over shaped glyphs. It prefers whitespace clusters
when the next shaped glyph is safe to break before, recognizes soft hyphen,
zero-width space, hyphen-like separators, and common CJK/Kana/Hangul adjacent
break opportunities, and falls back to hard shaped-glyph boundaries for
overlong text. It never splits inside a shaped glyph.

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
  provider.
- `pixie` and `hybrid` render through Pixie's rune raster path.

Selection and hit testing use source ranges, not glyph ids.

## Regression Coverage

The test suite covers:

- Shaped glyph ids and source ranges.
- Ligature source mapping and source-rune iteration.
- Wrapping at shaped glyph boundaries.
- Preserving ligature ranges on one line.
- CJK wrapping without whitespace using the dependency test font.
- Combining marks and Hebrew marks through source-range selection and hit
  testing.
- Mixed LTR/RTL source-range hit testing and caret-position helpers.
- Arabic shaping when a suitable named system Arabic font is available.
- Pure Harfbuzzy glyph-id rasterization.

## Future Extensions

- Full Unicode Line Breaking Algorithm tailoring for locale-specific wrapping.
- Widget-level editing policy, including arrow-key behavior, selection
  extension, and IME integration.
- Font fallback across shaped runs.
