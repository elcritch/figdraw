# Changes

## 0.39.0

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
