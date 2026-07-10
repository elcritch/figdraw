# Font Ownership

This document describes a possible ownership model for font-backed glyph images.
The goal is to let FigDraw track which renderer image-cache entries belong to a
specific font identity and make those entries eligible for automatic cleanup when
the font is no longer in use.

This is a design note. The current implementation keeps global font/typeface
registries and renderer-local image atlas entries, but it does not yet track
image ownership by font.

## Current State

`FigFont` is the public value object that describes a font:

- `typefaceId`
- `size`
- `lineHeight`
- case, underline, strikethrough, kerning settings
- fallback typefaces
- OpenType feature settings
- variable font coordinates

`FigFont.hash` includes these fields for layout identity. `FontId` is a raster
identity derived from the resolved typeface, size, case transform, variable
coordinates, and `figUiScale()`, so shaping-only settings do not duplicate
identical glyph images.

Glyph cache identity is currently:

```nim
hash((2344, glyph.fontId, glyph.glyphId, lcdFiltering, subpixelVariant))
```

That is enough to avoid collisions between font configurations and glyph
variants. It is not enough for eviction because renderer backends only store
image ids as atlas entries:

```nim
entries: Table[Hash, Rect]
```

The global image queue also tracks only whether an image id has been queued:

```nim
imageCached: HashSet[ImageId]
```

As a result, FigDraw can answer "is this image cached?", but cannot answer
"which cached glyph images belong to this `FontId`?"

## Goals

- Track glyph image ownership by `FontId`.
- Allow renderer-local removal of all glyph images for a font.
- Keep `FigFont` as an ordinary ARC/ORC-managed value object.
- Work with regular `--mm:arc` and `--mm:orc`, not only `--mm:atomicArc`.
- Avoid calling GPU APIs from destructors or non-render threads.
- Preserve the current simple user-facing font API.

## Non-Goals

- Do not make every `FigFont` copy retain/release renderer resources.
- Do not require applications to compile with `--mm:atomicArc`.
- Do not immediately solve complete atlas memory reuse. Logical eviction and
  physical atlas compaction can be separate phases.
- Do not evict user-loaded images just because font glyphs are evicted.

## Image Ownership Metadata

Add ownership metadata beside image ids:

```nim
type
  ImageOwnerKind* = enum
    iokNone
    iokFontGlyph

  ImageOwner* = object
    case kind*: ImageOwnerKind
    of iokNone:
      discard
    of iokFontGlyph:
      fontId*: FontId
      glyphId*: FontGlyphId
      lcdFiltering*: bool
      subpixelVariant*: uint8

  ImageCacheEntry* = object
    rect*: Rect
    owner*: ImageOwner
    width*, height*: int
```

Backends can keep the existing `entries` table for drawing compatibility and add
a richer side table:

```nim
imageEntries: Table[Hash, ImageCacheEntry]
fontImages: Table[FontId, HashSet[Hash]]
```

When a glyph image is uploaded, the backend records:

- image id to atlas rect
- image id to owner metadata
- font id to image id

For non-font images, `owner.kind` is `iokNone`.

## Upload API

Extend `ImgObj` so queued uploads can carry ownership:

```nim
type
  ImgObj* = object
    id*: ImageId
    owner*: ImageOwner
    case kind*: ImgKind
    of FlippyImg:
      flippy*: Flippy
    of PixieImg:
      pimg*: Image
```

Glyph generation can pass owner metadata through both upload paths:

```nim
proc glyphImageOwner(
  glyph: GlyphPosition,
  lcdFiltering: bool,
  subpixelVariant: int,
): ImageOwner =
  ImageOwner(
    kind: iokFontGlyph,
    fontId: glyph.fontId,
    glyphId: glyph.glyphId,
    lcdFiltering: lcdFiltering,
    subpixelVariant: uint8(subpixelVariant),
  )
```

Render-time misses currently call `ctx.putImage(glyphId, img)` directly. That
path should grow an overload or option object:

```nim
method putImage*(
  ctx: BackendContext,
  key: Hash,
  image: Image,
  owner: ImageOwner,
) {.base.}
```

The existing overload can delegate with `ImageOwner(kind: iokNone)`.

## Renderer Cache API

Expose renderer-level helpers instead of requiring callers to know backend
internals:

```nim
type
  ImageCacheStats* = object
    entries*: int
    fontGlyphEntries*: int
    logicalBytes*: int
    atlasSize*: int

proc clearFontImages*[BackendState](
  renderer: FigRenderer[BackendState],
  fontId: FontId,
): int

proc imageCacheStats*[BackendState](
  renderer: FigRenderer[BackendState],
): ImageCacheStats
```

Backend methods:

```nim
method removeImage*(ctx: BackendContext, key: Hash): bool {.base.}
method clearFontImages*(ctx: BackendContext, fontId: FontId): int {.base.}
method imageCacheStats*(ctx: BackendContext): ImageCacheStats {.base.}
```

`clearFontImages` should flush pending draw batches first, then remove the image
ids from `entries`, `imageEntries`, and `fontImages`.

## Font Lease

Automatic cleanup should use a separate lease object, not hooks on `FigFont`.

`FigFont` is copied through styles, layout spans, bindings, and tests. Giving it
custom refcount hooks would make ordinary value copies affect renderer cache
state. A separate lease makes the lifetime contract explicit while keeping the
existing font value API intact.

Sketch:

```nim
type
  FontLease* = object
    p: ptr FontLeasePayload

  FontLeasePayload = object
    refs: Atomic[int]
    fontId: FontId

proc retainFont*(fontId: FontId): FontLease
proc retainFont*(font: FigFont): FontLease
proc fontId*(lease: FontLease): FontId
```

The payload should use `allocShared` / `deallocShared` because it may cross
threads. The payload should only store simple shared-safe data such as `FontId`
and an atomic count. It should not store `FigFont`, `seq`, `string`, `Table`, or
renderer objects.

Ownership hooks follow the existing shared-handle pattern used by ARC/ORC code:

```nim
proc `=destroy`*(lease: FontLease) =
  if lease.p != nil:
    if lease.p.refs.fetchSub(1, moAcquireRelease) == 1:
      enqueueFontRelease(lease.p.fontId)
      deallocShared(lease.p)

proc `=wasMoved`*(lease: var FontLease) =
  lease.p = nil

proc `=dup`*(src: FontLease): FontLease =
  if src.p != nil:
    discard src.p.refs.fetchAdd(1, moRelaxed)
  result.p = src.p

proc `=copy`*(dest: var FontLease, src: FontLease) =
  if src.p != nil:
    discard src.p.refs.fetchAdd(1, moRelaxed)
  `=destroy`(dest)
  dest.p = src.p
```

The destructor must only enqueue a release request. It must not call renderer or
GPU APIs directly.

## Release Queue

Last lease release can happen on any ARC/ORC thread. Renderer cleanup must happen
on the render thread. Use a small queue:

```nim
type
  FontReleaseRequest* = object
    fontId*: FontId

var fontReleaseChan = newRChan[FontReleaseRequest](1024)
```

At the beginning of `renderRoot`, drain pending requests and mark zero-ref fonts
as eviction candidates:

```nim
while fontReleaseChan.tryRecv(req):
  ctx.markFontImagesUnused(req.fontId)
```

The renderer can either clear immediately or wait until cache pressure:

- immediate: simplest and deterministic
- delayed: avoids churn when a font disappears for one frame and returns
- pressure-based: best long-term behavior for large documents or editors

The recommended default is delayed eviction with a short grace period measured
in frames.

## Atlas Reuse

Phase one can remove `entries` and metadata. That makes glyphs logically evicted:
future draws will miss and regenerate them. It does not reclaim atlas pixels
because current backends allocate atlas space monotonically through a height-map
allocator.

Physical memory reuse needs one of these follow-up designs:

- free-list allocator: track free rectangles and reuse space for equal or smaller
  images
- page atlas: store glyphs in pages and release whole empty pages
- periodic rebuild: keep source metadata for live entries, create a new atlas,
  and re-upload live images

For glyphs, rebuild is practical because glyph images can be regenerated from
`fontId + glyphId + lcdFiltering + subpixelVariant`. For user-loaded images,
rebuild requires retained source pixels or a reload path. User images should
stay out of font-driven eviction unless they also have rebuild metadata.

## Suggested Implementation Phases

1. Add `ImageOwner`, `ImageCacheEntry`, and backend side tables.
2. Route glyph uploads through owner-aware `loadImage` / `putImage` paths.
3. Add `clearFontImages` and `imageCacheStats`.
4. Add tests for owner metadata and logical eviction with a fake or minimal
   backend.
5. Add `FontLease` and the font release queue.
6. Drain release requests at render-frame boundaries.
7. Add delayed or pressure-based eviction policy.
8. Add atlas reuse or rebuild after logical eviction is stable.

## Open Questions

- Should `retainFont(FigFont)` register the font in `fontTable`, or require the
  caller to pass an already-resolved `FontId`?
- Should text layout objects hold `FontLease` values, or should higher-level UI
  widgets own leases?
- Should zero-ref font glyphs be cleared immediately in tests but delayed in
  runtime builds?
- Should font eviction also clear shaped-layout caches if those are added later?
- Should fallback fonts retain separate leases, or should a primary font lease
  retain its full fallback chain?

## Recommended Public Shape

Keep normal drawing code unchanged:

```nim
let font = FigFont(typefaceId: ubuntu, size: 18)
node.textLayout = typeset(box, [(fs(font), "Hello")], ...)
```

Add explicit cache ownership only where an application wants deterministic font
cache lifetime:

```nim
block:
  let fontLease = retainFont(font)
  drawDocumentWith(font)
# Release is enqueued when fontLease leaves scope.
```

For most users, renderer cache policy should be automatic. `FontLease` is mainly
for editors, document viewers, font pickers, and long-running applications that
load many font configurations over time.
