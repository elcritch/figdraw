# Changes

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
