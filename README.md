<img width="1600" height="480" alt="figdraw-banner" src="https://github.com/user-attachments/assets/6f6931e1-205b-47ec-b392-bc20850ae146" />

`figdraw` is a *pure* Nim rendering library for building and rendering 2D scene graphs (`Fig` nodes) with a focus on being small and easy to use.

Features:

- GPU Rendering with OpenGL / Metal / Vulkan!
- Rects & shadows default to SDF (signed-distance-field) primitives for crisp, dynamic, and low memory UI primitives
- Lightweight, multiplatform, and high performance by design! (few or no allocations for each frame)
- Thread-safe renderer pipeline. (render tree construction and preparation can be done off the main thread)
- Fast pure Nimtext rendering and layout using [Pixie](https://github.com/treeform/pixie/) by default
- Optional Harfbuzzy support for shaping and rendering more complex scripts, font fallback, ligatures, and variable fonts!
- Image rendering using a texture atlas.
- Supports layering and multiple "roots" per layer - great for menus, overlays, etc.
- SDF/MSDF (Multi-SDF) based glyph rendering.
- Linear gradients with 2 and 3 stop points.
- Fast Gaussian 2-pass node operation for fast background blurs.
- Clipping and layering support. 

## Quick Start

This part works best with a recent Atlas (>= 0.9.6) version:

```sh
# Try the repo:
git clone https://github.com/elcritch/figdraw
cd figdraw
atlas install --feature:windy --feature:sdl2

# Run an example:
nim c -r examples/windy_renderlist.nim
```

```sh
# Use as a dependency (in your own project):
atlas use https://github.com/elcritch/figdraw
```

Alternatively Nimble should work as well:
```sh
nimble install https://github.com/elcritch/figdraw
```

**NOTE**: If you get errors you may need to install a newer version of Nimble or Atlas that support "features".

### Install / Usage Notes

**IMPORTANT**: to use features like windy, you'll want to add it to requires:

```nim
requires "https://github.com/elcritch/figdraw[windy]"
```

Alternatively, you can just `atlas use windy`.

## Programs Built with FigDraw

- [Neonim](https://github.com/elcritch/neonim) - cross platform GUI backend for Neovim.

## What's It Look Like?

Here's the primary rounded rect primitive with corners, borders, and shadows:

<img width="715" height="652" alt="Screenshot 2026-02-19 at 1 18 45 PM" src="https://github.com/user-attachments/assets/032bf60c-ff75-4165-a153-04d6eccec1cf" />

Here's it running as an overlay on top of a 3D scene:

<img width="1012" height="781" alt="Screenshot 2026-02-20 at 12 56 09 AM" src="https://github.com/user-attachments/assets/73a0eb3d-23f0-471c-bf61-1f35fa0946ed" />


Here's text rendering curtesy of Pixie. Note that Pixie's layout can be used or custom layout, e.g. for monospaced renderers:

<img width="1012" height="740" alt="Screenshot 2026-02-20 at 12 58 46 AM" src="https://github.com/user-attachments/assets/10de11d1-c528-4c25-9afd-38d282ecd800" />


Here's a video example (unfortunately capped at 30fps) of real time shadows, borders, and corners chaning fluidly at 120 FPS:

https://github.com/user-attachments/assets/aca4783c-86c6-4e52-9a16-0a8556ad1300

## Status

This repo is still under development but the core support for SDF is running! 
OpenGL backend is the only supported renderer right now
(`src/figdraw/opengl/`). However there's some work toward supporting Vulkan.

Future directions may include adding support for SDF textures for text rendering using Valve's SDF-text mapping technique. Other directions in that area would be supporting vector images rasterized to SDF textures as well. 

The next big item is hopefully setting up some examples of doing WebGL version with Windy.

Finally there will be a C API and a setup to compile FigDraw as a shared library. 

## Requirements

- Nim `>= 2.0.10` (ARC/ORC-based memory managers; required by `src/figdraw/common/rchannels.nim`)
- OpenGL (desktop GL by default; GLES/emscripten shader paths via `-d:useOpenGlEs` and/or `-d:emscripten`)

## Using Library

The most stable entry points today are:

- Core types/utilities: `import figdraw/commons`
- Scene graph nodes: `import figdraw/fignodes`
- OpenGL backend: `import figdraw/figrender`

Render list example (build a small scene tree):

```nim
import figdraw/commons
import figdraw/fignodes
import chroma

proc makeRenders(w, h: float32): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  let rootIdx = result.addRoot(0.ZLevel, Fig(
    kind: nkRectangle,
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 255),
  ))

  discard result.addChild(0.ZLevel, rootIdx, Fig(
    kind: nkRectangle,
    screenBox: rect(80, 60, 240, 140),
    fill: rgba(220, 40, 40, 255),
    corners: [12.0'f32, 12.0, 12.0, 12.0],
    stroke: RenderStroke(weight: 3.0, fill: rgba(0, 0, 0, 255)),
  ))
```

Feed the resulting `Renders` into the OpenGL backend; see the examples below for a full render loop.

For a complete working example (window + GL context + render loop), see:

- `examples/windy_renderlist.nim`
- `examples/sdl2_renderlist.nim`

### Image Cache Management

Image IDs are the stable, thread-safe handles for image nodes. `ImageRef` is the
convenience owner you keep in app state when you want FigDraw to retain an image
while it is visible or preloaded.

#### Automatic Management with `ImageRef`

```nim
type GalleryItem = object
  image: ImageRef
  frame: Rect

var visible: seq[GalleryItem]

proc show(path: string, frame: Rect) =
  visible.add GalleryItem(image: loadImageRef(path), frame: frame)

proc imageNode(item: GalleryItem): Fig =
  Fig(
    kind: nkImage,
    screenBox: item.frame,
    image: imageStyle(item.image),
  )

proc hide(index: int) =
  visible.delete(index) # drops the ImageRef; final release queues eviction
```

For scrolling folders or galleries, keep a visible set plus a small preload
margin. Hold `ImageRef`s in the app's gallery/cache state for visible and
preloaded images. UI nodes still use raw `ImageId`s from `imageRef.id`, so render
data stays cheap, copyable, and thread-safe.

Do not create a short-lived `ImageRef` only to copy its ID into a longer-lived
node:

```nim
block:
  let image = loadImageRef("photos/frame-001.png")
  node.image = imageStyle(image)

# `image` has expired here. The node still has an ImageId, but the final
# ImageRef release may queue the image for eviction before the node is rendered.
```

Keep the `ImageRef` alive for at least as long as any visible/preloaded node may
use its ID.

A `Table[ImageId, ImageRef]` or `Table[string, ImageRef]` is also fine when the
key helps reconcile scroll state; the important part is that the value being held
is the `ImageRef`.

#### Manual Management with `ImageId`

You can still work directly with raw IDs and manual clears when you want explicit
control:

```nim
let id = loadImage("photos/frame-001.png")

# Later, when the image scrolls out of the active range:
clearImage(id)

# Or clear several IDs at once:
clearImages([id])
```

`clearImage(id)` and `clearImage(imageRef)` make that image reloadable and remove
its renderer atlas lookup entry. They do not compact or reclaim holes inside the
packed texture atlas. Use `clearImageCache()` or `clearImageCache(renderer)` as
the memory relief path when the atlas grows past a budget; this resets the atlas
storage and currently visible images should be loaded again by the application.

### Font Cache Management

Typefaces are loaded as `TypefaceId`s. `FontRef` is the convenience owner for a
concrete `FigFont` and its rendered glyph cache. Keep the `FontRef` in app state
while visible or preloaded text may render with that font, and pass `fontRef.font`
to APIs that still need a raw `FigFont`.

#### Automatic Management with `FontRef`

```nim
type LabelItem = object
  font: FontRef
  text: string
  frame: Rect

let uiTypeface = loadTypeface("data/Ubuntu.ttf")
var labels: seq[LabelItem]

proc showLabel(text: string, frame: Rect) =
  labels.add LabelItem(
    font: fontRef(uiTypeface, 18.0'f32),
    text: text,
    frame: frame,
  )

proc textNode(item: LabelItem): Fig =
  Fig(
    kind: nkText,
    screenBox: item.frame,
    textLayout: typeset(
      item.frame,
      [span(item.font, rgba(20, 20, 20, 255), item.text)],
      minContent = false,
      wrap = true,
    ),
  )

proc hideLabel(index: int) =
  labels.delete(index) # drops the FontRef; final release queues glyph eviction
```

Do not create a short-lived `FontRef` only to copy its `FigFont` into a
longer-lived text node or layout:

```nim
block:
  let font = fontRef(uiTypeface, 18.0'f32)
  label.textLayout = typeset(
    label.screenBox,
    [span(font, rgba(20, 20, 20, 255), "Title")],
    minContent = false,
    wrap = true,
  )

# `font` has expired here. The layout may still reference glyph atlas entries,
# but the final FontRef release may queue those glyphs for eviction.
```

Keep the `FontRef` alive for at least as long as any visible/preloaded text
layout may render with that font.

#### Manual Management with Font IDs

You can still clear glyph caches explicitly when you want direct control:

```nim
let
  uiTypeface = loadTypeface("data/Ubuntu.ttf")
  uiFont = FigFont(typefaceId: uiTypeface, size: 18.0'f32)

let layout = typeset(
  rect(0, 0, 320, 48),
  [span(uiFont, rgba(20, 20, 20, 255), "Cached glyphs")],
  minContent = false,
  wrap = true,
)

# Clear glyphs for this exact FigFont:
let fontId = uiFont.convertFont()[0]
clearFontGlyphs(fontId)

# Or force-clear through a FontRef you already hold:
let uiFontRef = fontRef(uiFont)
clearFontGlyphs(uiFontRef)

# Or clear all glyphs rendered from the typeface:
clearTypefaceGlyphs(uiTypeface)
```

`clearFontGlyphs(fontId)` removes cached glyph atlas entries for one concrete
font. `clearFontGlyphs(fontRef)` works when you already hold a managed font. If
you import `figdraw/common/typefaces` directly, `clearFontGlyphs(font)` is also
available for a `FigFont`. `clearTypefaceGlyphs(typefaceId)` removes glyphs for
all sizes and styles using that typeface. `clearImageCache()` resets the shared
atlas storage, so glyphs and images should be regenerated or reloaded by the
application after a full reset.

### Managed Ref Threading

`ImageRef` and `FontRef` are thread-affine convenience wrappers. Pass raw
`ImageId`, `FontId`, `TypefaceId`, or `FigFont` values between threads, then
create a new ref on the target thread if that thread needs ownership. Moving or
sharing `ImageRef`/`FontRef` values across threads is unsupported in this
additive layer. A final ref release queues an eviction hint; the render thread
clears only after all owner tokens for that ID are gone. Manual clear APIs remain
force-clear requests.

### Atlas Usage Queries

Use `atlasUsageSnapshot()` for cheap cross-thread monitoring. It returns the last
usage value published by the render thread, so it may be one or more frames stale
but does not walk backend tables or block on the renderer:

```nim
type
  GallerySlot = object
    path: string
    frame: Rect

  GalleryItem = object
    image: ImageRef
    frame: Rect

var visible: seq[GalleryItem]

proc loadVisible(slots: openArray[GallerySlot]) =
  visible.setLen(0)
  for slot in slots:
    visible.add GalleryItem(
      image: loadImageRef(slot.path),
      frame: slot.frame,
    )

proc resetAtlasIfNeeded[BackendState](
    renderer: FigRenderer[BackendState],
    slots: openArray[GallerySlot],
) =
  let usage = atlasUsageSnapshot()
  if usage.snapshotId > 0 and usage.packedRatio() > 0.85'f32:
    visible.setLen(0)          # release old ImageRefs before the full reset
    clearImageCache(renderer)
    loadVisible(slots)         # reload the currently visible/preloaded images
```

For exact render-thread inspection, query the renderer directly:

```nim
let usage = renderer.atlasUsage()
echo "atlas: ", usage.atlasSize, "px"
echo "live entries: ", usage.entryCount
echo "packer full: ", usage.packedRatio()
```

`usedArea` is the sum of live image, glyph, and generated entries. `packedArea`
is the atlas packer's high-water estimate, including margins and holes left by
cleared entries. For streaming folders, prefer `packedRatio()` when deciding
when to call `clearImageCache(renderer)` and rebuild the visible/preloaded set.

### RenderList Tree Helpers

`addRoot` and `addChild` append nodes to the end of a layer. Use the insert helpers when draw order
or child order matters:

- `insertRoot(root, rootPos)`: inserts a root at `rootPos` in `rootIds`.
- `insertChild(parentIdx, child, childPos)`: inserts a child at `childPos` within a parent.
- `addChildren(parentIdx, children)`: appends roots from another `RenderList` as children.
- `insertChildren(parentIdx, children, childPos)`: inserts roots from another `RenderList` as children
  at `childPos`.

Each helper updates parent indexes, root indexes, and `childCount` after insertion. Batch helpers
preserve internal parent-child relationships from the incoming `RenderList`; incoming roots become
children of `parentIdx`.

Cost note: `addRoot` and `addChild` are amortized O(1) appends. The insert helpers are O(n) in the
target `RenderList` because they may shift nodes, rewrite parent/root indexes, and recompute child
counts. Batch helpers are O(n + m), where `m` is the inserted `RenderList` size, because inserted
nodes are also copied and remapped.

The `Renders` overloads take a `ZLevel` and force inserted nodes to that layer's zlevel:

```nim
var renders = Renders(layers: initOrderedTable[ZLevel, RenderList]())

let root = renders.addRoot(0.ZLevel, Fig(
  kind: nkRectangle,
  screenBox: rect(0, 0, 300, 200),
  fill: rgba(245, 245, 245, 255),
))

discard renders.insertChild(0.ZLevel, root, Fig(
  kind: nkRectangle,
  screenBox: rect(20, 20, 80, 60),
  fill: rgba(43, 159, 234, 255),
), 0)

var menuItems = RenderList()
discard menuItems.addRoot(Fig(
  kind: nkRectangle,
  screenBox: rect(24, 90, 120, 32),
  fill: rgba(40, 40, 40, 255),
))

discard renders.addChildren(0.ZLevel, root, menuItems)
```

## Transform Nodes

Use `nkTransform` as a non-drawing container to apply transforms to descendants.

- `transform.translation`: simple UI-space translation for all children
- `transform.matrix` + `transform.useMatrix = true`: optional extra matrix applied after translation

Example:

```nim
let tx = result.addChild(0.ZLevel, rootIdx, Fig(
  kind: nkTransform,
  transform: TransformStyle(
    translation: vec2(20.0'f32, 10.0'f32),
    matrix: scale(vec3(1.2'f32, 1.2'f32, 1.0'f32)),
    useMatrix: true,
  ),
))

discard result.addChild(0.ZLevel, tx, Fig(
  kind: nkRectangle,
  screenBox: rect(80, 60, 120, 80),
  fill: rgba(220, 40, 40, 255),
))
```

## Gradients (Fill API)

FigDraw uses `Fill` everywhere a color-style value is needed:

- `Fig.fill`
- `RenderStroke.fill`
- `RenderShadow.fill`
- text span styles (`fs` / `span`)

API:

- Solid fill: `fill(rgba(...))`
- Linear 2-stop: `linear(start, stop, axis = fgaX|fgaY|fgaDiagTLBR|fgaDiagBLTR)`
- Linear 3-stop: `linear(start, mid, stop, axis = ..., midPos = 128'u8)`

`midPos` is `0..255` and controls where the middle stop lands along the gradient axis.
`ColorRGBA` values (like `rgba(...)`) are accepted directly where `Fill` is expected.

Example (box + stroke + text span gradient):

```nim
import figdraw/commons
import figdraw/fignodes
import chroma

proc makeGradientDemo(w, h: float32, uiFont: FigFont): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  let panelFill = linear(
    rgba(255, 236, 168, 255),
    rgba(255, 178, 116, 255),
    axis = fgaY,
  )
  let strokeFill = linear(
    rgba(255, 120, 66, 255),
    rgba(72, 197, 255, 255),
    axis = fgaDiagTLBR,
  )
  let titleFill = linear(
    rgba(255, 120, 66, 255),
    rgba(252, 220, 128, 255),
    rgba(72, 197, 255, 255),
    axis = fgaX,
    midPos = 96'u8,
  )

  let root = result.addRoot(0.ZLevel, Fig(
    kind: nkRectangle,
    screenBox: rect(0, 0, w, h),
    fill: rgba(245, 245, 245, 255),
  ))

  discard result.addChild(0.ZLevel, root, Fig(
    kind: nkRectangle,
    screenBox: rect(40, 40, 360, 180),
    fill: panelFill,
    corners: [14.0'f32, 14.0, 14.0, 14.0],
    stroke: RenderStroke(weight: 3.0, fill: strokeFill),
  ))

  let titleLayout = typeset(
    rect(0, 0, 320, 50),
    [
      span(uiFont, rgba(20, 20, 20, 255), "FigDraw "),
      span(uiFont, titleFill, "OpenGL"),
    ],
    wrap = false,
  )

  discard result.addChild(0.ZLevel, root, Fig(
    kind: nkText,
    screenBox: rect(60, 70, 320, 50),
    textLayout: titleLayout,
    # For nkText: glyph colors come from span fills. `fill` is used for selection highlight.
    fill: rgba(255, 235, 170, 255),
  ))
```

## Font Shaping with Harfbuzzy

FigDraw uses Pixie text layout by default. For complex scripts, glyph ligatures,
font fallback, OpenType features, and variable-font axes, compile with the
optional Harfbuzzy backend.

Install the optional Harfbuzzy dependency when trying the repo:

```sh
atlas install --feature:windy --feature:harfbuzz
```

The pure glyph-id raster backend requires HarfBuzz 7.0 or newer plus FriBidi.
For example, install `libharfbuzz-dev libfribidi-dev` on Ubuntu or
`harfbuzz fribidi` with Homebrew before compiling it.

Add the `harfbuzz` feature when using FigDraw from another project:

```nim
requires "https://github.com/elcritch/figdraw[windy,harfbuzz]"
```

Note: Windy is the default example. Harfbuzz support works with Siwin, Surfer or other windowing libraries.

Then compile with the Harfbuzzy text backend:

### windy example
```sh
nim r -d:figdrawTextBackend=harfbuzzy examples/windy_text_shaping_demo.nim
```

### surfer example
```sh
nim r -d:figdrawTextBackend=harfbuzzy examples/surfer_text_shaping_demo.nim
```

For an example or app that should always use Harfbuzzy, put the backend switch
in a sibling `.nims` file:

```nim
# examples/windy_text_shaping_demo.nims
switch("define", "figdrawTextBackend=harfbuzzy")
```

The public text API stays FigDraw-owned: use `typeset` as usual, but pass
shaping controls through `FigFont`.

```nim
import figdraw/commons
import figdraw/common/fonttypes
import chroma

let
  ui = loadTypeface("data/Ubuntu.ttf")
  arabic = loadTypeface("examples/fonts/NotoNaskhArabic-wght.ttf")
  hebrew = loadTypeface("examples/fonts/NotoSansHebrew-wdth-wght.ttf")

  bodyFont = FigFont(
    typefaceId: ui,
    size: 22.0'f32,
    fallbackTypefaceIds: @[arabic, hebrew],
    features: @[fontFeature("kern"), fontFeature("liga")],
    variations: @[fontVariation("wght", 560.0'f32)],
  )

let layout = typeset(
  rect(0, 0, 520, 120),
  [span(bodyFont, rgba(30, 34, 40, 255), "Hello שלום السلام")],
  minContent = false,
  wrap = true,
)
```

Useful backend modes:

- `-d:figdrawTextBackend=pixie`: default Pixie layout and raster path.
- `-d:figdrawTextBackend=harfbuzzy`: Harfbuzzy shaping with glyph-id
  rasterization.
- `-d:figdrawTextBackend=hybrid`: Harfbuzzy layout converted through the Pixie
  compatibility raster path, useful for diagnostics.

When shaping is enabled, one visual glyph is not necessarily one source rune.
Use the source-aware helpers for selection, hit testing, and carets:

- `selectionRectsFor(sourceRange)`: merged visual selection bands for source
  rune ranges.
- `glyphSelectionRectsFor(sourceRange)`: raw per-glyph rectangles for
  diagnostics.
- `sourceRuneRangeAt(point)`: source range under a local text-layout point.
- `caretPositionsFor(sourceRune)`: visual caret rectangles for a source
  insertion index, including split positions at bidi boundaries.

Font collection paths (`.ttc` and `.otc`) are supported; FigDraw selects the
face whose name best matches the requested font and carries that face index
through shaping and rasterization. The current Harfbuzzy raster path renders
monochrome outlines, not color bitmap, SVG, or COLR glyph paint data.

See [docs/font_shaping.md](docs/font_shaping.md) for the data model details and
[examples/windy_text_shaping_demo.nim](examples/windy_text_shaping_demo.nim) for
a complete Arabic, Hebrew, Devanagari, fallback, and ligature demo.

## Layers and ZLevel

`Renders` is an ordered table of `ZLevel -> RenderList`. Lower zlevels are drawn first, so higher
zlevels appear on top. Each layer can contain multiple roots (useful for overlays, HUDs, menus, etc).

Short example:

```nim
import figdraw/commons
import figdraw/fignodes
import chroma

proc makeRenders(w, h: float32): Renders =
  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())

  discard result.addRoot(0.ZLevel, Fig(
    kind: nkRectangle,
    screenBox: rect(0, 0, w, h),
    fill: rgba(245, 245, 245, 255),
  ))

  discard result.addRoot(10.ZLevel, Fig(
    kind: nkRectangle,
    zlevel: 10.ZLevel,
    screenBox: rect(40, 40, 220, 120),
    fill: rgba(43, 159, 234, 255),
    corners: [10.0'f32, 10.0, 10.0, 10.0],
  ))

  result.layers.sort(proc(x, y: auto): int = cmp(x[0], y[0]))
```

## MSDF Bitmap based SDF Rendering

This has many benefits over regular textures for rendering vector shapes. It acts as a sort of "compression" technique allow us to scale the size of the shape while maintaining sharp edges with small texture sizes. Generally 64x64 can scale up to a fullscreen object with reasonable quality.

The other benefit is being able to draw shadows / strokes / etc similar to regular SDFs! See the blue stroked start below using the same SDF glyph as the others:

<img width="1136" height="780" alt="Screenshot 2026-02-03 at 5 56 30 PM" src="https://github.com/user-attachments/assets/728e7b59-d8db-4408-bc50-637742237022" />


See [examples/windy_msdf_star.nim](examples/windy_msdf_star.nim) for more info.

## Run Tests

Runs all tests + compiles all examples listed in `config.nims`:

```sh
nim test
```

Run a single test:

```sh
nim r tests/trender_rgb_boxes.nim
```

## SDF Rendering (default)

The OpenGL backend renders rounded rectangles and shadows using an SDF shader
path by default:

```sh
nim r examples/windy_renderlist.nim
```

To force the older texture path, compile with `-d:useFigDrawTextures`.

Notes:

- The main OpenGL shader combines atlas sampling and SDF rendering, switching per-draw via an `sdfMode` attribute (no shader swaps for SDF vs atlas).
- Masks still use a separate mask shader program.
- Current SDF modes include clip/AA fills, annular (outline) modes, and drop/inset shadow modes used by the renderer.

## Fast Rect Masks

Use `NfClipContent` when a node needs normal clipping semantics. It renders a mask and applies it to the node's content, which is flexible but can force the backend to flush queued draws around the mask pass.

Use `NfRectMaskContent` when the mask shape is just the node's rounded rectangle and the content is small leaf-style UI content, such as cells in a list/table, clipped buttons, pills, badges, or compact panels. On Metal this is evaluated as a per-fragment rounded-rect SDF mask, so it can avoid the extra mask pass for the first active rect mask and keep more draw work batched. Other backends fall back to the normal mask behavior, so the flag is safe to use before every backend has a fast implementation.

`NfRectMaskContent` also composes with `NfClipContent`: a scroll viewport can use `NfClipContent`, while each small child item inside it uses
`NfRectMaskContent`.

Example:

```nim
let viewport = result.addRoot(0.ZLevel, Fig(
  kind: nkRectangle,
  screenBox: rect(24, 24, w - 48, h - 48),
  fill: rgba(235, 238, 244, 255),
  corners: [12'u16, 12'u16, 12'u16, 12'u16],
  flags: {NfClipContent},
))

let row = result.addChild(0.ZLevel, viewport, Fig(
  kind: nkRectangle,
  screenBox: rect(32, 40, w - 64, 28),
  fill: rgba(255, 255, 255, 255),
  corners: [6'u16, 6'u16, 6'u16, 6'u16],
  flags: {NfRectMaskContent},
))

# These children can overflow `row`; `NfRectMaskContent` masks them to the
# row's rounded rectangle.
discard result.addChild(0.ZLevel, row, Fig(
  kind: nkRectangle,
  screenBox: rect(20, 44, w - 40, 8),
  fill: rgba(43, 159, 234, 255),
  corners: [3'u16, 3'u16, 3'u16, 3'u16],
))
```

To compare the two paths on your machine:

```sh
nim r examples/windy_clip_mask_benchmark.nim
```

The benchmark renders a table-like scene and compares `clip + sub-clip` against
`clip + rect-mask`.

## Debug Helpers

Import `figdraw/debugtools` for lightweight render-tree inspection helpers. `figVisibility` reports whether a `Fig` is disabled, clipped out, covered by a later opaque rectangle, or visible; `hitsAtPoint` and `topFigAtPoint` inspect clipped bounding-box hits in render order; `colorAt` samples a rendered `Image` or reads one pixel from a backend framebuffer. These helpers are intentionally conservative: clipping and hits use axis-aligned rectangles, and coverage detection handles simple later opaque rectangle covers rather than arbitrary partial overdraw.

## Useful Defines

- `-d:figdraw.names=true`: enables `Fig.name` for debugging (enabled for tests in `tests/config.nims`)
- `-d:useOpenGlEs`: select GLES/emscripten shader sources when GLSL 3.30 is not available
- `-d:useFigDrawTextures`: force the legacy texture-based shape rendering path (disables SDF shapes)
- `-d:openglMajor=3 -d:openglMinor=3`: override the requested OpenGL version (see `src/figdraw/utils/glutils.nim`)

## Text Runtime Flags

Text rendering exposes three runtime toggles:

- `renderer.setTextLcdFiltering(true|false)`
- `renderer.setTextSubpixelPositioning(true|false)`
- `renderer.setTextSubpixelGlyphVariants(true|false)`

Equivalent env vars (read at renderer initialization):

- `FIGDRAW_TEXT_LCD_FILTERING=1` (alias: `FIGDRAW_TEXT_LCD_FILTER`)
- `FIGDRAW_TEXT_SUBPIXEL_POSITIONING=1`
- `FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS=1`

When subpixel positioning is enabled, glyph-variant mode switches from UV-shift
sampling to pre-baked 10-step glyph variants for A/B comparison.

These are implemented for OpenGL and Vulkan backends. Other backends ignore them for now.

## Thread Safety Notes

- Rendering is structured so that preparing render lists/trees can be done off-thread.
- GPU resource submission (OpenGL calls) must happen on the GL thread; the backend enforces this separation.

## License

See `LICENSE`.
