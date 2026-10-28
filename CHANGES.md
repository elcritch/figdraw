# Changes

## Unreleased

- Switch the Vulkan renderer to vk14 while keeping context-local dispatch and
  Vulkan 1.0 fallback. The vk14 backend requires a 64-bit target and Nim 2.2.4
  or newer.
- Select Harfbuzzy automatically when HarfBuzz and FriBidi are available at
  runtime, falling back to Pixie otherwise. Existing layouts retain their
  rasterizer when the selected backend changes.

## 0.46.2

- Require released Harfbuzzy `^= 0.5.1` for the optional HarfBuzz backend,
  replacing the temporary outline API commit pin. This uses the merged upstream
  `harfbuzz-nim` bindings and their static C++ and Windows fixes.
- Use Harfbuzzy's current library override names in Windows and bundled-static
  CI checks.
- Fix fallback script lookup with Harfbuzzy's runtime imports in C++ and Windows
  builds, and check C++ effect compatibility in CI.

## 0.46.1

- Use Harfbuzzy's 0.5.0 glyph outline API and managed font handles, removing
  FigDraw's raw HarfBuzz draw bindings and callbacks. Pin the outline API commit
  while upstream PR #4 is pending. The optional backend now requires Nim
  2.2.10 and Unix `pkg-config` discovery.
- Use the `harfbuzz-nim` static-support PR through Harfbuzzy for Unix C
  bundled-static builds, retaining the Windows/C++ compatibility backend.

## 0.46.0

- Rasterize cached shape/glyph images with sdfy, with native uirelays or final
  Pixie composition for software Siwin. Skip software/uirelays backdrop blur.
- Add the native `uirelays_renderlist_100` launcher with the same options as
  `siwin_uirelays_renderlist_100`, including fixed corners by default.
- Block on Siwin events in the static pure software example instead of
  continuously redrawing an unchanged scene.
- Make native renderlist stress examples move cached images by default; opt in
  to size/shadow animation with `figdraw.animateShapes`. Use a configurable
  128 MiB example cache, report hits/misses, and avoid copying cached pixel
  buffers while choosing an eviction candidate.
- Draw aligned solid square fills through uirelays' native rectangle relay,
  retaining mixed native/image screenshot order. Remove the stress example's
  redundant background image and keep oversized images from flushing its cache
  after maximizing the window.
- Fix software square Bézier caps, clamped MSDF/MTSDF edge sampling, and small
  fractional-scale uirelays frame sizes found during Astra review.
- Redraw the static uirelays example only when invalidated and wait for events
  while idle; keep the renderlist stress scene continuously animated.
- Track uirelays' `feat/rgba-alpha` branch for premultiplied-alpha drawing,
  native blocking Siwin event waits, refresh notification suppression, and
  reusable RGBA upload slots.
- Present directly to Siwin software-window pixel buffers with backing-scale
  layout, resize-safe buffer acquisition, RGBA/BGRA conversion, and Pixie
  composition for opaque windows. Add a Harfbuzzy-default `siwin_software`
  example sharing sdfy SIMD and automatic workers without uirelays or a GPU
  presentation context.
- Use automatic internal Sigils worker pools for large software rounded
  draws and masks, with disjoint row tiles and a barrier after each draw.
  Add `figdraw.threadedSdfy` and `figdraw.sdfySimd` boolean build options;
  software renderers lazily use up to four workers without application setup.
- Use sdfy's borrowed span API for software rounded fills, strokes, shadows,
  and masks. Vectorize gradients, affine coordinates, coverage, mask
  multiplication, and premultiplied blending in addition to distance fields.
- Retain software example scenes and fonts across redraws to avoid repeated
  font discovery, file loading, and logging.
- Render uirelays frames and glyphs at display backing resolution. Preserve
  Cocoa contents during live resize through the pinned uirelays fixes.
- Add `siwin_uirelays.nim`, selecting siwin and Harfbuzzy by default.
- Batch rounded-shape distances using SSE2/NEON in software fills, strokes,
  shadows, nested masks, and backdrop-blur boundaries. Prepare radii once per
  draw and use the circular kernel where possible. Preserve affine sampling,
  scalar tails, gradients, and premultiplied compositing.
- Require released sdfy 0.8.5 for SIMD span rendering.

- Add an experimental sdfy software backend with elliptical corners, gradients,
  shadows, clipping, curves, distance images, and the existing glyph layout API.
- Add optional uirelays presentation through its native, siwin, or Windy driver.
  Use uirelays 0.11.0 and sdfy's elliptical-corner support.

## 0.45.0

- Respect Harfbuzzy's static linking option when importing glyph-drawing
  functions, so glyph rasterization does not load a second HarfBuzz library.
- Require Harfbuzzy 0.3.0 for dynamic and static builds.
- Use concrete query-parameter iterators with Windy to support Nim devel.

## 0.44.0

- Use Siwin's platform ABI fixes and reusable X11 visual/XCB helpers.
  Pin upstream Siwin with merged [#58](https://github.com/levovix0/siwin/pull/58).
- Accept Siwin's `uint64` Vulkan surfaces without losing their upper bits;
  retain pointer inputs for other window backends.
- Mark recursive fragment and diagnostic render trees acyclic; rely on Nim
  inference for other render data. Document the downward ownership contract.
- Add cross-thread ARC/ORC render-data coverage and fragment-cycle rejection
  regressions.
- Borrow the host window in the Siwin renderer and its OpenGL fallback state,
  breaking the window/callback/renderer cycle. Callers keep the window alive
  through rendering and renderer cleanup.
- Add `finishPendingFrames` to wait for submitted Metal, Vulkan, or OpenGL work
  before releasing a presentation target. Renderer types remain cycle-capable.

## 0.42.0

- Add immutable shared glyph arrangements and glyph-range views for line render
  nodes. Frozen arrangements discard redundant position and selection arrays
  when arranged glyphs contain the same geometry.
- Add `typesetSourceSpans` and its measurement variant for compact
  `StyledTextRun` ranges and a separate `FontStyle` table. Layouts retain the
  shared `Utf8Runes` source. Pixie reuses it for display text when unchanged
  and maps converted or filtered glyphs back to original source byte ranges.
  Harfbuzzy shapes normal-case ranges without keeping a string per styled run.
- Expose sparse rune/byte position lookup on `Utf8Runes` so callers can create
  byte ranges without a dense index.
- Preserve the existing Pixie typesetting and arrangement-conversion proc
  signatures, keep fonts and colors aligned when Pixie filters a whole control
  span, and raise `ValueError` when borrowing bytes from a nil `Utf8Runes`.

## 0.41.0

- Allocate Metal backdrop and rect-mask storage on first use, release optional
  textures on resize or after three frames without blur, and avoid duplicate CPU
  index and screenshot buffers.

- Move the ownership-safe fixed-ring RChan implementation and its regression
  suite to Sigils 0.31.0; keep a compatibility import for existing FigDraw
  callers and exercise image-message replacement through the shared channel.

- Store `RChan` messages in a fixed typed ring, transferring isolated values
  with `swap` under the lock. Remove per-message allocations and send rollback;
  preserve `tryTake` sources on failure and receive isolated values directly.
  Initialize vacant slots without constructing payload field defaults.
- Release image-message subscription channels and all ring storage. Run payload
  hooks outside channel locks and reject reentrant operations during teardown.
- Add Linux/macOS RSS regressions covering both `tryRecv` and blocking `recv`.

## 0.40.2

- Export producer-owned `RenderFragments`, fragment handles, cursors, and their
  mutation/query API through the native dynamic-library facade. Render fragment
  trees can now be rendered directly through `figdraw/windowing`.
- Add the `imageStyle(ImageId, Fill)` overload to the native facade and preserve
  custom fills for both image IDs and image references.

## 0.39.0

- Expose `resetFontCache` and font/source/metadata lookups through the regular
  and native `figdraw` imports. Reset font registration and glyph caches together,
  preserving static typeface registrations and ordinary images by default.
- Export font metrics, glyph rasterization and selection helpers, and system-font
  discovery through the native facade. Keep font ownership and image-message
  subscriptions opaque; raise missing-cache lookup errors in the consumer using
  producer-side status-returning lookups.
- Hide native renderer, backend-state, and presentation-target fields behind
  Binny 0.5.12 opaque exports. Remove Cocoa/Metal type imports from the shared export
  configuration while preserving direct calls and producer-owned destruction.
  Keep the attached window in the facade for automatic UI-scale tracking.
- Forward explicit Metal, Vulkan, OpenGL, and OpenGL-fallback defines into the
  native producer build, preserving `=off` values and effective Vulkan linking.
  Export the direct dedicated-render capability queries and render-thread
  transition alongside the existing presentation-target APIs.
- Export Pixie's RGBA setter/fill and Siwin renderer frame/presentation APIs
  directly. Return `SiwinRenderer` from `newFigSiwinApp`; remove `NativeSiwinApp`
  and the scalar fused-frame adapter. Keep facade lazy setup, defaults, and
  automatic UI-scale tracking while replacing dummy presentation/frame APIs.
- Share system typeface identities and font variations between producer and
  consumers; use direct exact-file loading and sizing instead of copying
  metadata in the facade.
- Export the typed Siwin renderer's backend queries and text preferences
  directly with Binny 0.5.11. Remove native and facade forwarding APIs plus
  manual opaque-handle ownership hooks. Expose `app.renderer` from an
  ARC-managed app while retaining automatic UI-scale and frame orchestration.
- Export Pixie's pixel getter directly with shared Chroma `ColorRGBX`, keeping
  straight-alpha conversion in the dynlib facade instead of a producer adapter.
  Require Binny 0.5.10 for the imported-alias and nil-overload fixes.
- Use the direct backend-kind naming API instead of an app-specific native
  name forwarder.
- Export Siwin interactive move/resize, window-menu, and raw icon methods
  directly. Keep only facade conversions for optional positions and borrowed
  image pixels, including the distinct clear-icon call.
- Export Pixie's image factory, copy, file reader, and PNG overloads directly
  with Binny 0.5.9. Remove duplicate image setter, fill, and icon facade
  forwarders while keeping alpha and icon-format conversions.
- Reuse Bumpy, Vmath, Chroma, Rune, and stdlib Slice types in native bindings
  without boundary casts. Remove `IntSlice` and `FigSelectionRange` bridge
  aliases; text selection ranges use `Slice[int16]` directly. Export UTF-8
  constructors, scale/font helpers, Bezier overloads, Pixie codecs,
  and sink-based image uploads directly instead of maintaining duplicates.
- Export Siwin windows, events, clipboard operations, and platform methods
  directly from the native dynamic library without compiling Siwin in clients.
  Create windows with `newSiwinWindow`, then attach FigDraw rendering with
  `newFigSiwinApp(window, atlasSize, pixelScale)`; remove the legacy window
  records, pointer forwarders, and C-callback bridge while retaining semantic
  converters, constructor defaults, and the renderer ownership handle.
- Store `GlyphArrangement` source and display text as UTF-8 with sparse rune
  indexes in both static and native dynamic-library builds, reducing retained
  text-layout memory while preserving indexed rune access plus compatibility
  with sequence literals and `seq[Rune]` APIs.
- Expose explicit generated native operations for indexing, slicing, iteration,
  and compatibility conversions.

## 0.37.4

- Transform Vulkan content-clip bounds into framebuffer coordinates so translated
  views retain their text and decorations.

## 0.37.3

- Select the owning OpenGL context before image preparation, atlas rebuilds,
  rendering, and screenshots so native popups cannot redirect another window's
  atlas uploads.
- Preserve atlas pixels during growth, accept exact-width images, upload
  single-pixel images, and validate update sizes in all build modes.
- Flush pending draws before image updates and recover pixel coordinates
  correctly for non-power-of-two atlas sizes.
- Initialize atlas padding and extrude image edges; use base-level filtering to
  prevent shared mipmaps from mixing entries. Flippy atlas uploads use their base
  image; standalone textures retain mipmap support.
- Isolate pixel transfer strides and PBO bindings, establish popup draw state,
  correct transparent backdrop blur, and release replaced textures on resize.
- Add OpenGL atlas/context regressions and require graphics in Linux X11/Wayland
  CI for both GPU backends.

## 0.37.2

- Keep Vulkan atlas images and descriptor sets alive until submitted work completes.
  Atlas growth preserves existing images and accepts exact-width allocations.
- Give each recorded upload and draw its own staging/uniform slice, including blur
  passes, so later changes cannot overwrite earlier commands in the same frame.
- Keep Vulkan dispatch local to each context and its resources so creating or
  closing a popup cannot redirect another window's Vulkan calls.
- Use presentation semaphores per swapchain image, defer retired swapchain
  resources, and explicitly transition acquired images before rendering.
- Correct premultiplied image/backdrop sampling and honor nearest-neighbor atlas
  sampling. Skip backdrop copies when the swapchain cannot be a transfer source.
- Validate atlas sizes against allocation/device limits and retain Vulkan error
  checks in danger builds.
- Add Vulkan atlas, popup, blur, and resource-lifetime regressions plus optional
  synchronization validation in Linux X11/Wayland CI.
