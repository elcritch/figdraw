# Font Shaping Plan

This plan describes how to add HarfBuzz-based shaping as a compile-time
alternative to the current Pixie text path.

## Goals

- Keep the existing FigDraw text API usable for callers.
- Support shaped glyph output: glyph ids, advances, offsets, and source
  clusters.
- Keep Pixie as the default font backend until the HarfBuzz path is complete.
- Avoid leaking HarfBuzz handles or FFI details into public FigDraw node APIs.
- Preserve current glyph atlas, LCD filtering, subpixel positioning, selection,
  and renderer behavior where possible.

## Current Design

FigDraw currently uses Pixie for three separate jobs:

- Font loading and metrics in `src/figdraw/common/typefaces.nim`.
- Text layout in `src/figdraw/common/fontutils.nim` via `pixie.typeset`.
- Glyph image generation in `src/figdraw/common/fontglyphs.nim`, keyed by
  `(fontId, rune, filtering, subpixelVariant)`.

That works for simple Unicode glyph lookup, but shaped text needs glyph identity
from the font rather than Unicode runes. Arabic joining, ligatures, Hebrew marks,
and OpenType substitutions can all produce glyph ids that do not map cleanly to a
single input rune.

## Backend Selection

Add a compile-time text backend switch:

```nim
const fontBackend {.strdefine: "figdraw.fontBackend".} = "pixie"

when fontBackend == "harfbuzz":
  import ./textbackends/harfbuzz as textbackend
elif fontBackend == "pixie":
  import ./textbackends/pixie as textbackend
else:
  {.error: "unknown figdraw.fontBackend".}
```

The public `typeset`, `loadTypeface`, and `FigFont` APIs should remain stable.
Backend-specific handle types stay private to backend modules.

## Module Layout

Proposed split:

- `common/fonttypes.nim`
  Backend-neutral public data types.
- `common/typefaces.nim`
  Public font loading API, static registry, ids, and backend dispatch.
- `common/textbackends/pixie.nim`
  Current Pixie implementation moved behind the backend interface.
- `common/textbackends/harfbuzz.nim`
  HarfBuzz shaping implementation using `../harfbuzzy`.
- `common/fontglyphs.nim`
  Backend-neutral glyph iteration, glyph cache keys, and rasterization dispatch.
- `common/textbidi.nim`
  Later bidi/run-itemization layer. Not part of the first HarfBuzz slice.

## Data Model

Add backend-neutral shaped glyph data:

```nim
type
  GlyphIndex* = distinct uint32

  ArrangedGlyph* = object
    fontId*: FontId
    glyphId*: GlyphIndex
    cluster*: uint32
    rune*: Rune
    pos*: Vec2
    advance*: Vec2
    offset*: Vec2
    rect*: Rect
```

Update `GlyphArrangement` to either store `glyphs*: seq[ArrangedGlyph]` or to
carry equivalent parallel arrays during migration. Keep the existing
`runes`, `positions`, and `selectionRects` populated until current renderer and
tests are moved over.

`rune` should be treated as source/debug metadata. Rendering and caching must use
`glyphId`.

## HarfBuzz Flow

For each shaped run:

1. Resolve `FigFont` to a backend font record.
2. Build HarfBuzz shape options from direction, script, language, flags, and
   features.
3. Shape text with `harfbuzzy`.
4. Convert HarfBuzz font units to FigDraw pixels:

   ```nim
   px = hbPosition.float32 * (font.size / face.upem.float32)
   ```

5. Accumulate pen position from `xAdvance` and `yAdvance`.
6. Apply `xOffset` and `yOffset` to the glyph draw position.
7. Store `glyph.codepoint` as `GlyphIndex`.
8. Store `glyph.cluster` for selection, hit testing, and source mapping.

HarfBuzz lays out one run. FigDraw remains responsible for paragraph layout,
line wrapping, horizontal alignment, vertical alignment, min/max content, and
selection rectangles.

## Glyph Rasterization

The renderer can stay mostly unchanged if `GlyphPosition` becomes glyph-id
based.

Required changes:

- Change glyph cache key from `(fontId, rune, filtering, subpixelVariant)` to
  `(fontId, glyphId, filtering, subpixelVariant)`.
- Skip invisible glyphs by glyph metadata or extents, not only by
  `rune.isWhiteSpace`.
- Render glyph images by `fontId + glyphId`.

Rasterization options:

1. Use HarfBuzz `hb-raster` to render glyph masks or BGRA color glyph images.
   HarfBuzz 14.x exposes CPU raster APIs such as `hb_raster_draw_glyph`,
   `hb_raster_draw_render`, and `hb_raster_paint_glyph`.
2. Use HarfBuzz `hb-gpu` for direct GPU outline/color-glyph rendering. This is
   a larger renderer integration because FigDraw would upload HarfBuzz-encoded
   glyph blobs and use HarfBuzz shader snippets instead of the current bitmap
   atlas path.
3. Extend Pixie/OpenType to expose `getGlyphPath(glyphId)` and keep Pixie as the
   rasterizer. This is still useful if FigDraw wants to keep all glyph cache
   output as Pixie `Image`s.
4. Add a FreeType-backed rasterization path later.
5. Keep a temporary rune path only for Pixie compatibility. This does not solve
   Arabic shaping or ligatures.

The first useful HarfBuzz implementation should use either HarfBuzz `hb-raster`
or Pixie glyph-id paths, depending on whether it is easier to extend
`../harfbuzzy` or Pixie's OpenType surface first. HarfBuzz `hb-gpu` should be a
separate later project because it bypasses FigDraw's current image-atlas model.

## Bidi

HarfBuzz does not perform bidi processing. The first slice can support explicit
single-direction runs.

Full mixed-direction support needs:

- Paragraph bidi analysis, probably FriBidi or ICU.
- Visual run ordering.
- Logical-to-visual and visual-to-logical cluster mapping.
- Line-level reordering after wrapping.

This should live outside the HarfBuzz backend so the shaping backend receives
same-direction runs.

## `harfbuzzy` Gaps

Before relying on `../harfbuzzy` for FigDraw, add or verify:

- `addUtf8(text, itemOffset, itemLength)` so shaping runs can use full paragraph
  context.
- Public buffer cluster-level setters around existing raw
  `hb_buffer_set_cluster_level`.
- Proper glyph flag extraction, especially `unsafe_to_break`.
- `typefaceFromBlob` or `initTypeface(data)` for FigDraw's static typeface
  registry.
- A stable way to retrieve face `upem`, extents, glyph extents, and glyph
  advances without exposing raw handles.
- Bindings and wrappers for HarfBuzz rendering APIs if FigDraw uses HarfBuzz for
  rasterization:
  - `hb-draw` / `hb_font_draw_glyph_or_fail` for vector outlines.
  - `hb-raster` for CPU glyph masks and BGRA color glyph output.
  - `hb-gpu` only if FigDraw adopts HarfBuzz's GPU glyph encoding path.

## Migration Phases

1. Add `GlyphIndex` and shaped glyph fields while preserving existing Pixie
   behavior.
2. Move the current Pixie implementation behind `textbackends/pixie.nim`.
3. Change glyph cache and renderer code to use `glyphId`.
4. Add glyph-id rasterization through HarfBuzz `hb-raster` or Pixie glyph-id
   paths.
5. Add `textbackends/harfbuzz.nim` for unidirectional runs.
6. Add tests comparing Latin Pixie and HarfBuzz layout for simple text.
7. Add Arabic and Hebrew fixture tests with known fonts.
8. Add bidi itemization and mixed-direction selection tests.

## Tests

Focused tests should cover:

- Existing Pixie backend behavior under default build flags.
- `-d:figdraw.fontBackend=harfbuzz` compile and smoke tests.
- Static font registry loading through the HarfBuzz backend.
- Glyph cache separation by glyph id, LCD filtering, and subpixel variant.
- Arabic shaping with a font such as Noto Naskh Arabic.
- Hebrew marks with a font such as Noto Sans Hebrew.
- Ligature clusters and selection rectangles.
- Mixed LTR/RTL text after bidi support is added.

## Open Questions

- Should `GlyphArrangement` expose shaped glyphs directly, or keep an iterator as
  the only stable access surface?
- Should line wrapping happen before shaping for simple text or after shaping
  using HarfBuzz `unsafe_to_break` flags?
- Which bidi dependency should FigDraw prefer: FriBidi, ICU, or a small Nim
  implementation?
- Should HarfBuzz be a package feature, a compile-time define only, or both?
