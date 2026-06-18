# Font Shaping Design

This document tracks FigDraw's HarfBuzz-backed shaping design through
`harfbuzzy` while keeping the integration local to FigDraw. Harfbuzzy stays an
external shaping library; FigDraw owns the adapters, backend switch, layout
conversion, glyph identity, source mapping, and raster-provider decisions.

The core design choice is glyph-id-first text layout. Users can still get the
source rune cheaply, but rendering, cache keys, and glyph placement do not
depend on runes.

## Goals

- Keep existing user-facing text calls such as `typeset`, `loadTypeface`, and
  `FigFont` stable.
- Make `fontId + glyphId` the canonical render/cache identity.
- Preserve cheap source-rune access for callers, debugging, whitespace checks,
  and compatibility with current tests and examples.
- Keep Pixie as the default backend while Harfbuzzy wrapping and mixed-direction
  selection mature.
- Keep HarfBuzz behind a compile-time text backend without leaking HarfBuzz
  handles into FigDraw node APIs.
- Keep adapter work in FigDraw, even if it wraps Pixie or Harfbuzzy APIs that
  are not shaped exactly for FigDraw.

## Current Baseline

FigDraw has a glyph-id-first text layout path with these important constraints:

- `fontutils.typeset` is still the stable public entry point.
- `GlyphArrangement.arrangedGlyphs` is the canonical glyph placement data.
- `GlyphArrangement.runes`, `positions`, and `selectionRects` remain for
  compatibility while callers migrate to `glyphs`.
- `fontId + glyphId` is the canonical render/cache identity.
- `rune`, `sourceRunes`, and source-range helpers preserve cheap access to the
  original text.
- Pure `harfbuzzy` mode renders shaped glyph ids through the FigDraw-local
  HarfBuzz draw raster provider.
- `pixie` and `hybrid` keep Pixie's rune raster path; `hybrid` is diagnostic,
  not a complex-script rendering target.

## Remaining Work

- Full shaped-run line wrapping using cluster break metadata.
- Bidi and mixed-direction selection support beyond the current visual-run
  shaping order.
- Additional complex-script regression tests for Arabic, Hebrew marks,
  combining marks, and mixed LTR/RTL text.

## Backend Selection

FigDraw uses a string compile-time switch so all modes are explicit:

```nim
const figdrawTextBackend* {.strdefine.} = "pixie"

static:
  doAssert figdrawTextBackend in ["pixie", "harfbuzzy", "hybrid"]
```

Expected profiles:

- `pixie`: current Pixie layout and Pixie rasterization. This remains the
  default, but `GlyphArrangement` still carries glyph ids.
- `hybrid`: Harfbuzzy shaping can be converted into FigDraw arrangements for
  diagnostics and early layout tests, but rendering remains Pixie-compatible
  where possible. This mode is not a correctness target for complex scripts.
- `harfbuzzy`: Harfbuzzy shapes text and FigDraw renders by shaped glyph id
  through the glyph-id raster provider. Full wrapping and bidi behavior remain
  layout-layer work.

Hide the switch behind a backend facade:

```nim
when figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid":
  import ./textbackends/harfbuzzy as textBackend
else:
  import ./textbackends/pixie as textBackend
```

`fontutils.typeset` stays as the stable public entry point and delegates to the
selected backend.

## Module Layout

Current split:

- `common/fonttypes.nim`
  Backend-neutral public data types.
- `common/typefaces.nim`
  Public font loading API, static registry, ids, and backend dispatch.
- `common/textbackends/pixie.nim`
  Current Pixie implementation behind the backend interface.
- `common/textbackends/harfbuzzy.nim`
  Harfbuzzy shaping adapter and conversion into FigDraw arrangements.
- `common/textrasters/pixie_raster.nim`
  Pixie compatibility raster provider.
- `common/textrasters/glyphid_raster.nim`
  Glyph-id raster provider using HarfBuzz draw callbacks and Pixie path filling.
- `common/fontglyphs.nim`
  Backend-neutral glyph iteration, glyph cache keys, and raster dispatch.

## Glyph Identity

FigDraw uses a font-scoped glyph id type instead of `Rune` as the render
identity:

```nim
type
  FontGlyphId* = distinct uint32
```

`FontGlyphId` is scoped by `FontId` and the selected raster provider. In
Harfbuzzy mode it is the HarfBuzz glyph codepoint. In Pixie compatibility mode
it may be a stable synthetic id derived from the source rune until FigDraw has a
true Pixie glyph-id path.

Do not reuse the existing `GlyphId` name for this. `GlyphId` currently means an
image/cache id derived from a hash. If needed later, rename that cache id
separately to reduce ambiguity.

## Data Model

Keep glyph identity, source mapping, and cheap source-rune access together:

```nim
type
  GlyphSourceRange* = object
    byteStart*: int  # inclusive
    byteEnd*: int    # exclusive
    runeStart*: int  # inclusive
    runeEnd*: int    # exclusive

  ArrangedGlyph* = object
    fontId*: FontId
    glyphId*: FontGlyphId
    cluster*: uint32
    source*: GlyphSourceRange
    rune*: Rune          # cheap first/source rune for compatibility
    isWhitespace*: bool
    pos*: Vec2
    advance*: Vec2
    offset*: Vec2
    imageOffset*: Vec2
    rect*: Rect
```

`GlyphArrangement` prefers arranged glyphs:

```nim
type
  GlyphArrangement* = object
    contentHash*: Hash
    lines*: seq[Slice[int]]
    spans*: seq[Slice[int]]
    fonts*: seq[GlyphFont]
    spanColors*: seq[Fill]
    sourceRunes*: seq[Rune]
    arrangedGlyphs*: seq[ArrangedGlyph]
    runes*: seq[Rune]      # legacy compatibility
    positions*: seq[Vec2]  # legacy compatibility
    selectionRects*: seq[Rect]
    maxSize*: Vec2
    minSize*: Vec2
    bounding*: Rect
```

Compatibility note: keep the existing `runes` and `positions` parallel arrays
until callers move to `glyphs`. During migration:

- `runes[i]` should match `arrangedGlyphs[i].rune`, not claim to be the
  complete source text for shaped layouts.
- `positions[i]` should match `arrangedGlyphs[i].pos`.
- `sourceRunes` stores the decoded source runes for callers that need the full
  source range.

For cheap rune access, `glyph.rune` and `GlyphPosition.rune` stay populated.
For correctness, expose range helpers so users can tell when one glyph maps to
multiple source runes:

```nim
func sourceRune*(arrangement: GlyphArrangement, glyphIndex: int): Rune
func sourceRuneRange*(arrangement: GlyphArrangement, glyphIndex: int): Slice[int]
iterator sourceRunes*(arrangement: GlyphArrangement, glyphIndex: int): Rune
```

The first helper is O(1). `sourceRuneRange` returns an inclusive range suitable
for indexing `sourceRunes`, while the iterator hides the half-open
`GlyphSourceRange` storage detail from callers.

Source-range helpers use inclusive input and output `Slice[int]` values. They
return `0 .. -1` when no glyph intersects the requested source range:

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

## Glyph Position Iterator

`GlyphPosition` exposes the glyph-id-first shape without forcing users to learn
the whole arrangement object:

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

The iterator `glyphs(arrangement)` yields `GlyphPosition` values backed by
`arrangedGlyphs`. Render code uses `glyph.glyphId` for cache identity while
keeping `glyph.rune` for cheap whitespace/debug compatibility.

## Hashing And Rendering

Glyph cache identity is glyph-id-based:

```nim
proc hash*(glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0): Hash =
  hash((2344, glyph.fontId, glyph.glyphId, lcdFiltering, subpixelVariant))
```

Rendering rules:

- Skip invisible glyphs via `isWhitespace`, zero extents, or backend glyph flags.
- Use `fontId + glyphId` for image cache lookup.
- Keep `rune` in debug logs because it is cheap and human-readable.
- Selection and hit testing use `source`, not `glyphId`.

`generateGlyph` dispatches to a raster provider:

```nim
proc generateGlyph*(glyph: GlyphPosition, ...): Image =
  when figdrawTextBackend == "harfbuzzy":
    renderGlyphIdGlyph(..., glyph.fontId, glyph.glyphId, ...)
  else:
    renderPixieGlyph(..., glyph.fontId, glyph.rune, ...)
```

The Pixie provider ignores `glyphId` internally and rasters `glyph.rune`. That
is acceptable for the default Pixie path and hybrid diagnostics. The pure
Harfbuzzy path uses the glyph-id provider and renders the shaped glyph id.

## Adapter Boundaries

All adapter work lives in FigDraw. Public node and layout APIs expose FigDraw
types such as `FigFont`, `GlyphArrangement`, `ArrangedGlyph`, `FontGlyphId`,
and `GlyphSourceRange`, not HarfBuzz handles.

Future wrapping and bidi work should stay in the adapter/layout layer. The
selected backend may shape, rasterize, and report visual run order, but FigDraw
keeps ownership of paragraph layout, line boxes, selection mapping, and cache
identity.

## Harfbuzzy Flow

The current adapter gives future line-layout code these shaped-run facts:

- `glyph.codepoint` becomes `FontGlyphId`.
- `glyph.cluster` becomes the cluster key for source mapping and break logic.
- Source byte/rune ranges are stored as `GlyphSourceRange`.
- `xAdvance`, `yAdvance`, `xOffset`, and `yOffset` are converted to pixels:

   ```nim
   px = hbPosition.float32 * (font.size / face.upem.float32)
   ```

- `imageOffset` comes from glyph extents so raster images can include negative
  bearings while baseline placement stays stable.

HarfBuzz shapes runs. FigDraw remains responsible for paragraph layout, line
wrapping, horizontal alignment, vertical alignment, min/max content, and
selection rectangles.

## Wrapping And Selection

The first Harfbuzzy backend is a shaping adapter, not a full paragraph layout
replacement. Line breaking still needs to move onto shaped-run metadata such as
cluster boundaries and unsafe-to-break flags before Harfbuzzy mode should be
treated as wrapping-correct.

Selection helpers now support source ranges:

- Current glyph-index selection can keep working against `selectionRects`.
- `glyphRangeForSourceRunes` and `glyphRangeForSourceBytes` map source ranges
  to glyph ranges.
- `selectionRectsForSourceRunes` and `selectionRectsForSourceBytes` return
  selection rectangles for source ranges.
- `glyphIndexAt` and `sourceRuneRangeAt` provide local-point hit testing.
- Ligatures and combining marks may share source ranges across multiple glyphs
  or one glyph. Selection code must not assume one glyph equals one rune.

## Test Gaps

Future tests should cover:

- Arabic shaping with a font such as Noto Naskh Arabic.
- Hebrew marks with a font such as Noto Sans Hebrew.
- `sourceRunes(arrangement, glyphIndex)` for combining marks and complex-script
  clusters.
- Mixed LTR/RTL text after bidi support is added.

## Open Questions

- Should the old `GlyphArrangement.runes` field eventually be deprecated in
  favor of `sourceRunes` plus `arrangedGlyphs[i].rune`?
- Should `FontId` include text backend, raster backend, and feature set so cache
  keys cannot collide across modes?
- Should `fontCase` remain a pre-shaping text transform shared by all backends?
