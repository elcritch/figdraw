# Thread-Safe Image And Font Cache Plan

## Goals

- [x] Keep `ImageId`, `FontId`, and `TypefaceId` as the primary thread-safe handles.
- [x] Let any thread request image upload or image clear without touching backend state directly.
- [x] Let any thread request full image atlas reset without touching backend state directly.
- [x] Let any thread request targeted font-glyph clear without touching backend state directly.
- [x] Use one ordered `ImageMsg` stream for new image upload and image clear work.
- [x] Keep the legacy `imageChan: RChan[ImgObj]` drained for source compatibility.
- [x] Let users manually clear images when streaming large folders.
- [x] Add an optional managed-handle layer that uses thread-local counts and sends retain/release messages.
- [x] Keep cache-clearing APIs additive so existing `ImageId`, `loadImage`, `FigFont`, and `loadTypeface` workflows keep working.

## Compatibility Commitments

- [x] Keep `loadImage*(filePath: string): ImageId` unchanged.
- [x] Keep `loadImage*(id: ImageId, image: Image)` unchanged.
- [x] Keep `hasImage*(id: ImageId): bool` unchanged.
- [x] Keep `ImageId` usable directly in `Fig.image.id`.
- [x] Keep `ImgObj`, `sendImage`, and `sendImageCached` as compatibility wrappers.
- [x] Keep the exported legacy `imageChan` source-compatible.
- [x] Implement compatibility wrappers by translating to `ImageMsg`.
- [x] Do not require users to adopt `ImageRef` or `FontRef`.
- [x] Keep the new `ImageMsg` channel private behind renderer helpers.
- [x] Treat backend atlas metadata as an internal implementation detail unless there is a clear public use case.

## Decisions

- [x] `clearImage(id)` is a force-clear request. It removes logical cache state and renderer atlas lookup state even if a managed ref exists later.
- [x] Managed ref final release is an eviction hint. It should clear only when the render thread sees no remaining owners for that ID.
- [x] Raw IDs are the cross-thread API. Pass `ImageId`, `FontId`, or `TypefaceId` between threads, not managed refs.
- [x] `ImageRef` and `FontRef` are thread-affine convenience wrappers. If another thread needs ownership, send the ID and create/retain a new wrapper there.
- [x] Add shared/atomic managed refs later only if callers need owned refs to cross thread boundaries.
- [x] Use `send` for image clear messages so important cache-control events are not dropped.
- [x] Use `send` for reset messages so important cache-control events are not dropped.
- [x] Use `send` for retain/release messages so important cache-control events are not dropped.
- [x] Reserve `push` only for future lossy update-style messages.
- [x] Keep generation state in `imgutils` behind a lock for phase 1, because uploads can be produced before the render thread sees them.
- [x] Do not clear `fontTable`, `typefaceTable`, or `typefaceSourceTable` in the first implementation.
- [x] Full atlas reset clears image and glyph atlas entries; visible user images must be reloaded by application logic.
- [x] Text glyphs are allowed to regenerate automatically after atlas reset.

## Thread-Safety Principles

- [x] Treat integer/hash IDs as the safe cross-thread resource handles.
- [x] Do not pass renderer/backend contexts across threads for image cache mutation.
- [x] Do not mutate GPU resources or atlas tables outside the render thread for image clear.
- [x] Destructors must never touch backend state directly.
- [x] Use channels to move image payloads and image clear requests to the render thread.
- [x] Keep cache generation state protected by a lock or owned by the render-thread message processor.
- [x] Serialize logical cache mutations and image-message enqueue order.
- [x] Prefer explicit message ordering over ad hoc direct calls.

## Image Message Channel

- [x] Add an internal `RChan[ImageMsg]` beside the legacy `RChan[ImgObj]`:

  ```nim
  type ImageMsgKind = enum
    ImkPutFlippy
    ImkPutPixie
    ImkPutGlyphPixie
    ImkClearImage
    ImkClearImages
    ImkClearImageCache
    ImkClearFontGlyphs
    ImkClearTypefaceGlyphs
  ```

- [x] Add message kinds for targeted font/glyph clears:

  ```nim
  type ImageMsgKind = enum
    imkClearFontGlyphs
    imkClearTypefaceGlyphs
  ```

- [x] Add message kinds for managed refs:

  ```nim
  type ImageMsgKind = enum
    ImkRetainImage
    ImkReleaseImage
    ImkRetainFont
    ImkReleaseFont
  ```

- [x] Define one message type for uploads and image clears:

  ```nim
  type ImageMsg = object
    generation: uint64
    cacheGeneration: uint64
    id: ImageId
    fontId: FontId
    typefaceId: TypefaceId
    ids: seq[ImageId]
    case kind: ImageMsgKind
    of ImkPutFlippy:
      flippy: Flippy
    of ImkPutPixie, ImkPutGlyphPixie:
      image: Image
    of ImkClearImage, ImkClearImages, ImkClearImageCache, ImkClearFontGlyphs,
        ImkClearTypefaceGlyphs:
      discard
  ```

- [x] Keep `ImgObj` as a compatibility upload payload.
- [x] Move or isolate image payloads when sending `ImkPutFlippy` or `ImkPutPixie`.
- [x] Keep clear messages ID-only so they are cheap and naturally thread-safe.
- [x] Drain image messages at the start of `renderRoot`.
- [x] Process new image messages in channel order.
- [x] Use `send` for important cache commands and consider `push` only for explicitly lossy update-style messages.

## Manual Cache APIs

- [x] Add logical image clearing that is safe from any thread:

  ```nim
  proc clearImage*(id: ImageId)
  proc clearImages*(ids: openArray[ImageId])
  ```

- [x] Implement these procs by updating logical cache generation state and sending `ImkClearImage` or `ImkClearImages`.
- [x] Add renderer convenience APIs that still enqueue messages instead of mutating backend state directly:

  ```nim
  proc clearImage*[BackendState](renderer: FigRenderer[BackendState], id: ImageId)
  proc clearImages*[BackendState](
    renderer: FigRenderer[BackendState], ids: openArray[ImageId]
  )
  ```

- [x] Add full atlas/cache reset:

  ```nim
  proc clearImageCache*()
  proc clearImageCache*[BackendState](renderer: FigRenderer[BackendState])
  ```

- [x] Implement full reset by sending `ImkClearImageCache`.
- [x] Add targeted glyph clears:

  ```nim
  proc clearFontGlyphs*(fontId: FontId)
  proc clearFontGlyphs*(font: FigFont)
  proc clearTypefaceGlyphs*(typefaceId: TypefaceId)
  ```

- [ ] Document that `clearImage(id)` makes an image reloadable and removes atlas lookup state, but does not reclaim packed atlas holes.
- [ ] Document that `clearImageCache(renderer)` is the memory relief path because it resets/recreates atlas storage.

## Stale Upload Protection

- [x] Maintain a generation for each `ImageId`.
- [x] Stamp every upload message with the generation observed when the image was loaded.
- [x] Increment an image generation when `clearImage(id)` is requested.
- [x] Increment a global cache generation when `clearImageCache()` or `clearImageCache(renderer)` is requested.
- [x] Skip `ImkPutFlippy` and `ImkPutPixie` messages whose generation is stale.
- [x] Let an explicit clear win over older in-flight uploads.
- [x] Allow a newer upload for the same `ImageId` after clear by stamping it with the new generation.

## Render-Thread Processing

- [x] On `ImkPutFlippy` or `ImkPutPixie`, upload to the backend atlas if the message generation is current.
- [x] On `ImkClearImage`, remove the image from backend entries.
- [x] On `ImkClearImages`, remove each listed image from backend entries.
- [x] On `ImkClearImage`, remove atlas metadata for matching user image entries.
- [x] On `ImkClearImages`, remove atlas metadata for matching user image entries.
- [x] On `ImkClearImageCache`, reset the whole atlas; the request path clears logical image/glyph cached state.
- [x] On `ImkClearFontGlyphs`, remove glyph atlas entries for the font.
- [x] On `ImkClearTypefaceGlyphs`, remove glyph atlas entries for fonts using that typeface.
- [x] On retain/release messages, update render-thread ownership tables used by the managed-handle layer.

## Atlas Metadata

- [x] Add metadata beside backend atlas entries:

  ```nim
  type AtlasEntryKind = enum
    aekImage
    aekGlyph
    aekGenerated

  type AtlasEntryMeta = object
    kind: AtlasEntryKind
    imageId: ImageId
    fontId: FontId
    typefaceId: TypefaceId
  ```

- [x] Mark user-loaded images as `aekImage`.
- [x] Mark generated glyph images as `aekGlyph`.
- [x] Mark shape/shadow/corner generated assets as `aekGenerated`.
- [x] Use metadata so image clears do not remove glyphs or generated renderer assets.
- [x] Use metadata so font clears only remove glyph entries.

## Backend Atlas Operations

- [x] Add backend methods:

  ```nim
  method removeImage*(ctx: BackendContext, id: ImageId) {.base.}
  method clearImageAtlas*(ctx: BackendContext) {.base.}
  ```

- [x] Add targeted font/glyph backend methods:

  ```nim
  method clearFontGlyphs*(ctx: BackendContext, fontId: FontId) {.base.}
  method clearTypefaceGlyphs*(ctx: BackendContext, typefaceId: TypefaceId) {.base.}
  ```

- [x] Implement `removeImage` and `clearImageAtlas` for OpenGL, Metal, and Vulkan.
- [x] `removeImage` should delete lookup entries; it does not reclaim skyline holes.
- [x] `clearImageAtlas` should flush pending draw batches before resetting backend atlas state.
- [x] Reset atlas texture to the initial size.
- [x] Clear backend `entries`.
- [x] Clear backend atlas metadata.
- [x] Reset skyline `heights`.
- [x] For Vulkan, recreate or mark atlas GPU storage dirty as appropriate.
- [x] Bump global cache generation during full reset.

## Managed Handle Layer

- [x] Keep managed handles additive and ID-based:

  ```nim
  type
    ImageRef* = object
      id*: ImageId

    FontRef* = object
      font*: FigFont
      fontId*: FontId
  ```

- [x] Avoid making `ImageRef` or `FontRef` the only way to use images/fonts.
- [x] Document that managed refs are thread-affine.
- [x] Document that raw IDs are the supported way to communicate resources across threads.
- [x] Maintain thread-local counts for cheap same-thread copies.
- [x] Allocate one stable `ownerToken` per thread.
- [x] On first local `ImageRef` retain for an ID, send `ImkRetainImage(id, ownerToken)`.
- [x] On last local `ImageRef` release for an ID, send `ImkReleaseImage(id, ownerToken)`.
- [x] On first local `FontRef` retain for a font, send `ImkRetainFont(fontId, ownerToken)`.
- [x] On last local `FontRef` release for a font, send `ImkReleaseFont(fontId, ownerToken)`.
- [x] The render thread should aggregate owner tokens per ID and clear only when the aggregate owner set is empty.
- [x] A final release should be an automatic eviction hint, not a direct forced clear from a destructor.
- [x] Manual `clearImage(id)` remains a force-clear request.
- [x] Do not automatically remove `typefaceTable` or `typefaceSourceTable` in the first version.

## Managed Constructors

- [x] Add image constructors:

  ```nim
  proc imageRef*(id: ImageId): ImageRef
  proc loadImageRef*(path: string): ImageRef
  proc imageRef*(id: ImageId, image: Image): ImageRef
  ```

- [x] Add font constructors:

  ```nim
  proc fontRef*(font: FigFont): FontRef
  proc fontRef*(typefaceId: TypefaceId, size: float32): FontRef
  ```

- [x] `loadImageRef(path)` should call the normal load path and return the ID wrapper.
- [x] `imageRef(id, image)` should upload through the image message channel and retain the ID.
- [x] `fontRef` should retain the `FontId` derived from the `FigFont`.

## Ownership Hook Rules

- [x] Keep destructors non-raising.
- [x] Destructors should only update thread-local counts and enqueue retain/release messages.
- [x] Do not mutate backend context, GPU resources, global image sets, or atlas tables from `=destroy`.
- [x] Declare custom hooks immediately after managed-handle type definitions.
- [x] Test copy, move, destroy-after-move, self-assignment, and final-release behavior.
- [x] Verify hooks with `--expandArc` before relying on destructor behavior.

## Streaming Folder Workflow

- [ ] App keeps a visible image set plus a preload margin.
- [ ] App stores `ImageId`s in UI nodes and may optionally hold `ImageRef`s for visible/preloaded images.
- [ ] App drops refs or calls `clearImage(id)` when images scroll out of range.
- [ ] Final `ImageRef` release sends a release message; the render thread clears only when no owner tokens remain.
- [ ] App calls `clearImageCache(renderer)` when atlas size or memory budget crosses a threshold.
- [ ] After a full cache reset, app reloads currently visible/preloaded image IDs.

## Phased Rollout

- [x] Phase 1: add `ImageMsg`, compatibility wrappers, generation tracking, and manual `clearImage`.
- [x] Phase 1: keep existing upload behavior working through wrappers.
- [x] Phase 1: add stale queued upload tests.
- [x] Phase 2: add backend `removeImage`, `clearImageAtlas`, and `clearImageCache(renderer)`.
- [x] Phase 2: add atlas reset tests for image cache state and glyph regeneration.
- [x] Phase 3: add atlas metadata and targeted font/glyph clears.
- [x] Phase 3: add tests proving image clears do not delete glyph/generated entries.
- [x] Phase 4: add `ImageRef` and `FontRef` thread-affine managed wrappers.
- [x] Phase 4: add ownership hook and owner-token aggregation tests.
- [ ] Phase 5: add docs/examples for streaming folders and memory-budget reset policy.

## Tests

- [x] `clearImage(id)` sends a clear message and increments the image generation.
- [x] `clearImage(id)` allows `loadImage(path)` and `loadImage(id, image)` to enqueue a newer upload.
- [x] Stale queued uploads are skipped after `clearImage(id)`.
- [x] `ImkClearImage` removes the backend entry.
- [ ] Drawing a cleared image does not crash.
- [x] `ImkClearImageCache` resets atlas entries and logical image markers.
- [x] Glyph generation regenerates markers after a full atlas reset.
- [x] `ImkClearFontGlyphs` removes only glyph entries for that font.
- [x] `ImkClearTypefaceGlyphs` removes only glyph entries for that typeface.
- [x] `ImageRef` first retain sends `ImkRetainImage`.
- [x] `ImageRef` final release sends `ImkReleaseImage`.
- [x] Releases from one thread do not clear an image still retained by another thread.
- [x] Passing raw `ImageId` across threads and creating a new `ImageRef` on the target thread retains under that thread's owner token.
- [ ] Moving or sharing `ImageRef` across threads is documented as unsupported in phase 4.
- [x] `FontRef` final release sends `ImkReleaseFont`.
- [x] Manual `clearImage(id)` overrides retained state by design.

## Implementation Order

- [x] Implement phase 1.
- [x] Run focused image tests.
- [x] Implement phase 2.
- [x] Run focused render/image/glyph tests.
- [x] Implement phase 3.
- [x] Run focused font/glyph tests.
- [x] Implement phase 4.
- [x] Run ownership hook tests under ARC/ORC.
- [ ] Implement phase 5.
- [ ] Run `nim test`.
