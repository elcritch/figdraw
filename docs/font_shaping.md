# Font Shaping Plan

This plan describes how FigDraw should add HarfBuzz-backed shaping through
`harfbuzzy` while keeping the work local to FigDraw. Harfbuzzy stays an external
shaping library; FigDraw owns the adapters, backend switch, layout conversion,
glyph identity, and raster-provider decisions.

The core design choice is glyph-id-first text layout. Users should still be able
to get the source rune cheaply, but rendering, cache keys, and glyph placement
should not depend on runes.

## Goals

- Keep existing user-facing text calls such as `typeset`, `loadTypeface`, and
  `FigFont` stable.
- Make `fontId + glyphId` the canonical render/cache identity.
- Preserve cheap source-rune access for callers, debugging, whitespace checks,
  and compatibility with current tests and examples.
- Keep Pixie as the default backend until the HarfBuzz path is complete.
- Add HarfBuzz as a compile-time text backend without leaking HarfBuzz handles
  into FigDraw node APIs.
- Implement required adapters in FigDraw, even if they wrap Pixie or Harfbuzzy
  APIs that are not shaped exactly for FigDraw.

## Implementation Status

Implemented in the first FigDraw-local slice:

- `FontGlyphId`, `GlyphSourceRange`, and `ArrangedGlyph` are public
  backend-neutral data types in `common/fonttypes.nim`.
- `GlyphArrangement` now carries `sourceRunes` and `arrangedGlyphs` while
  keeping the legacy `runes`, `positions`, and `selectionRects` arrays.
- `sourceRune`, `sourceRuneRange`, and `sourceRunes` provide cheap source-rune
  access from a glyph index.
- The Pixie path populates arranged glyphs using a Pixie-compatible synthetic
  glyph id scoped by `FontId`.
- `GlyphPosition` carries `glyphId`, `cluster`, `source`, `rune`, and
  `isWhitespace`.
- Glyph image cache hashing now uses `fontId + glyphId` instead of
  `fontId + rune`.
- The renderer skips whitespace through `glyph.isWhitespace`.

Implemented in the backend wiring slice:

- The public `fontutils.typeset` entry point now dispatches through
  `common/textbackends/pixie.nim` or `common/textbackends/harfbuzzy.nim`.
- `typefaces.nim` keeps FigDraw-owned source font bytes so adapters are not
  limited to path-backed fonts.
- The Harfbuzzy backend converts shaped glyph codepoints into `FontGlyphId`
  values and populates source byte/rune ranges.
- Pixie's rune-based glyph rendering now lives behind
  `common/textrasters/pixie_raster.nim` as the compatibility raster provider.

Still pending:

- Adding a glyph-id raster provider so shaped glyph ids can render correctly.
- Moving selection and hit testing from glyph-index assumptions toward source
  ranges.

## Current Design

FigDraw currently still uses Pixie for three separate jobs:

- Font loading and metrics in `src/figdraw/common/typefaces.nim`.
- Text layout in `src/figdraw/common/fontutils.nim` via `pixie.typeset`.
- Glyph image generation in `src/figdraw/common/fontglyphs.nim`.

That works for simple Unicode glyph lookup, but shaped text needs glyph identity
from the selected font. Arabic joining, ligatures, Hebrew marks, and OpenType
substitutions can produce glyph ids that do not map cleanly to one input rune.

Pixie's public API is also rune/text based. It does not currently expose a
public glyph-id raster path to FigDraw, so the default Pixie backend may need a
compatibility adapter that uses stable synthetic glyph ids while continuing to
raster through Pixie's source-rune APIs.

The current Pixie compatibility path now hashes cache entries by
`(fontId, glyphId, filtering, subpixelVariant)`, but the Pixie raster step still
uses `glyph.rune` internally.

## Backend Selection

Use a string compile-time switch so all modes are explicit:

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
- `harfbuzzy`: Harfbuzzy shapes text and FigDraw renders by shaped glyph id.
  This becomes correct only when a glyph-id raster provider is available.

Hide the switch behind a backend facade:

```nim
when figdrawTextBackend == "harfbuzzy" or figdrawTextBackend == "hybrid":
  import ./textbackends/harfbuzzy as textBackend
else:
  import ./textbackends/pixie as textBackend
```

`fontutils.typeset` should stay as the stable public entry point and delegate to
the selected backend.

Current status: `pixie`, `hybrid`, and `harfbuzzy` compile through the backend
facade. `hybrid` uses Harfbuzzy shaping with Pixie-compatible rune rastering for
diagnostics. `harfbuzzy` produces shaped glyph-id arrangements, but visual
rendering is not a correctness target until the glyph-id raster provider lands.

## Module Layout

Proposed split:

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
  Future glyph-id raster provider using HarfBuzz draw/raster APIs, FreeType, or
  another FigDraw-local adapter.
- `common/fontglyphs.nim`
  Backend-neutral glyph iteration, glyph cache keys, and raster dispatch.

## Glyph Identity

Add a font-scoped glyph id type instead of using `Rune` as the render identity:

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
    rect*: Rect
```

Update `GlyphArrangement` to prefer arranged glyphs:

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
    selectionRects*: seq[Rect]
    maxSize*: Vec2
    minSize*: Vec2
    bounding*: Rect
```

Migration note: keep the existing `runes` and `positions` parallel arrays until
the renderer and tests move to `glyphs`. During migration:

- `runes[i]` should match `arrangedGlyphs[i].rune`, not claim to be the
  complete source text for shaped layouts.
- `positions[i]` should match `arrangedGlyphs[i].pos`.
- `sourceRunes` stores the decoded source runes for callers that need the full
  source range.

For cheap rune access, keep `glyph.rune` and `GlyphPosition.rune` populated.
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

## Glyph Position Iterator

Update `GlyphPosition` without forcing users to learn the whole arrangement
shape:

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
    rect*: Rect
    descent*: float32
    lineHeight*: float32
    fill*: Fill
```

The iterator `glyphs(arrangement)` should yield `GlyphPosition` values backed by
`arrangedGlyphs`. Existing render code can move from `glyph.rune` to
`glyph.glyphId` for cache identity while keeping `glyph.rune` for cheap
whitespace/debug compatibility.

## Hashing And Rendering

Change glyph cache identity from rune-based to glyph-id-based:

```nim
proc hash*(glyph: GlyphPosition, lcdFiltering = false, subpixelVariant = 0): Hash =
  hash((2344, glyph.fontId, glyph.glyphId, lcdFiltering, subpixelVariant))
```

Rendering rules:

- Skip invisible glyphs via `isWhitespace`, zero extents, or backend glyph flags.
- Use `fontId + glyphId` for image cache lookup.
- Keep `rune` in debug logs because it is cheap and human-readable.
- Selection and hit testing use `source`, not `glyphId`.

`generateGlyph` should dispatch to a raster provider:

```nim
proc generateGlyph*(glyph: GlyphPosition, ...): Image =
  rasterProviderFor(glyph.fontId).renderGlyph(glyph)
```

The Pixie provider may initially ignore `glyphId` internally and raster
`glyph.rune`. That is acceptable only for the default Pixie path and hybrid
diagnostics. The Harfbuzzy correctness path needs a provider that can render
the shaped glyph id.

## FigDraw Adapters

All adapter work should live in FigDraw.

Pixie adapter:

- Convert Pixie's current `Arrangement` into `seq[ArrangedGlyph]`.
- Assign a stable `FontGlyphId` for each source rune. If Pixie does not expose a
  nominal font glyph id, use a synthetic id scoped by `FontId`.
- Populate `sourceRunes`, `GlyphSourceRange`, `rune`, and `isWhitespace`.
- Keep Pixie's existing one-rune raster path behind `pixie_raster.nim`.

Harfbuzzy adapter:

- Use Harfbuzzy's existing `ShapeContext`, `ShapedParagraph`, `ShapedRun`, and
  glyph output.
- Flatten runs into `ArrangedGlyph` values inside FigDraw.
- Compute source byte/rune ranges in FigDraw if Harfbuzzy does not provide the
  exact shape FigDraw wants.
- Convert Harfbuzzy positions to pixels using face `upem` and `FigFont.size`.
- Keep bidi/run-order handling in the adapter layer so FigDraw controls line
  layout and selection mapping.

Raster adapter:

- Prefer a FigDraw-local glyph-id raster provider.
- Options include HarfBuzz draw/raster raw APIs through a FigDraw wrapper,
  FreeType, or a FigDraw-local Pixie/OpenType bridge.
- Do not require upstream Harfbuzzy API changes before the FigDraw adapter can
  progress.

## Harfbuzzy Flow

For each shaped run:

1. Resolve `FigFont` to a FigDraw backend font record.
2. Build Harfbuzzy shape options from direction, script, language, flags, and
   features.
3. Shape text with Harfbuzzy.
4. Convert Harfbuzzy font units to FigDraw pixels:

   ```nim
   px = hbPosition.float32 * (font.size / face.upem.float32)
   ```

5. Accumulate pen position from `xAdvance` and `yAdvance`.
6. Apply `xOffset` and `yOffset` to the glyph draw position.
7. Store `glyph.codepoint` as `FontGlyphId`.
8. Store `glyph.cluster` and a FigDraw `GlyphSourceRange` for selection, hit
   testing, and cheap source-rune lookup.

HarfBuzz shapes runs. FigDraw remains responsible for paragraph layout, line
wrapping, horizontal alignment, vertical alignment, min/max content, and
selection rectangles.

## Wrapping And Selection

The first Harfbuzzy backend is a shaping adapter, not a full paragraph layout
replacement. Line breaking still needs to move onto shaped-run metadata such as
cluster boundaries and unsafe-to-break flags before Harfbuzzy mode should be
treated as wrapping-correct.

Selection should move toward source ranges:

- Current glyph-index selection can keep working against `selectionRects`.
- New helpers should map byte/rune source ranges to glyph ranges.
- Ligatures and combining marks may share source ranges across multiple glyphs
  or one glyph. Selection code must not assume one glyph equals one rune.

## Migration Phases

1. Done: add `FontGlyphId`, `GlyphSourceRange`, and `ArrangedGlyph`.
   Populate them from the existing Pixie backend with no behavior change.

2. Done: keep cheap rune compatibility.
   Keep `GlyphPosition.rune`, add `GlyphPosition.glyphId`, and add
   `sourceRune`/`sourceRunes` helpers.

3. Done: change glyph cache and renderer code to use `glyphId`.
   Keep logs, whitespace checks, tests, and compatibility helpers using
   `rune`.

4. Done: move the current Pixie implementation behind `textbackends/pixie.nim`
   and the Pixie compatibility raster path behind `textrasters/pixie_raster.nim`.
   `fontutils.typeset` delegates through the compile-time backend facade.

5. Done: add `textbackends/harfbuzzy.nim` for shaped runs.
   Convert Harfbuzzy glyph ids and positions into `ArrangedGlyph`.

6. Add a glyph-id raster provider.
   This is the point where `harfbuzzy` mode becomes correct for ligatures,
   Arabic joining, marks, and substitutions.

7. Add bidi and mixed-direction selection support.
   Keep it in FigDraw's adapter/layout layer, not in public node APIs.

## Tests

Focused tests now cover:

- Existing Pixie backend behavior under default build flags.
- `-d:figdrawTextBackend=harfbuzzy` and `hybrid` compile/smoke coverage for
  `tfontutils`.
- `GlyphPosition.glyphId` cache separation by LCD filtering and subpixel
  variant.
- `GlyphPosition.rune` and `sourceRune` remaining cheap and populated.
- Static font registry loading through the backend-specific `tfontutils` runs.
- `sourceRunes(arrangement, glyphIndex)` for current one-rune Pixie mappings
  and the current Harfbuzzy smoke shape.

Remaining tests should cover:

- Arabic shaping with a font such as Noto Naskh Arabic.
- Hebrew marks with a font such as Noto Sans Hebrew.
- Ligature clusters and selection rectangles.
- `sourceRunes(arrangement, glyphIndex)` for ligatures and combining marks.
- Mixed LTR/RTL text after bidi support is added.

## Open Questions

- Should the old `GlyphArrangement.runes` field eventually be deprecated in
  favor of `sourceRunes` plus `arrangedGlyphs[i].rune`?
- Should `FontId` include text backend, raster backend, and feature set so cache
  keys cannot collide across modes?
- Should `fontCase` remain a pre-shaping text transform shared by all backends?
- Which glyph-id raster provider should land first: HarfBuzz draw/raster APIs,
  FreeType, or a FigDraw-local Pixie bridge?
