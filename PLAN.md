# Thread-Safe Image And Font Cache Plan

## Goals

- [ ] Keep `ImageId`, `FontId`, and `TypefaceId` as the primary thread-safe handles.
- [ ] Let any thread request image upload, image clear, font-glyph clear, or atlas reset without touching backend state directly.
- [ ] Use one ordered channel message stream for image upload and cache-control work.
- [ ] Let users manually clear images when streaming large folders.
- [ ] Add an optional managed-handle layer that uses thread-local counts and sends retain/release messages.
- [ ] Keep all APIs additive so existing `ImageId`, `loadImage`, `FigFont`, and `loadTypeface` workflows keep working.

## Compatibility Commitments

- [ ] Keep `loadImage*(filePath: string): ImageId` unchanged.
- [ ] Keep `loadImage*(id: ImageId, image: Image)` unchanged.
- [ ] Keep `hasImage*(id: ImageId): bool` unchanged.
- [ ] Keep `ImageId` usable directly in `Fig.image.id`.
- [ ] Keep `ImgObj`, `sendImage`, and `sendImageCached` as compatibility wrappers if they are currently exported.
- [ ] Implement compatibility wrappers by translating to `ImageMsg`.
- [ ] Do not require users to adopt `ImageRef` or `FontRef`.
- [ ] Treat the `ImageMsg` channel and backend atlas metadata as internal implementation details unless there is a clear public use case.

## Decisions

- [ ] `clearImage(id)` is a force-clear request. It should remove logical cache state and renderer atlas lookup state even if a managed ref still exists.
- [ ] Managed ref final release is an eviction hint. It should clear only when the render thread sees no remaining owners for that ID.
- [ ] Raw IDs are the cross-thread API. Pass `ImageId`, `FontId`, or `TypefaceId` between threads, not managed refs.
- [ ] `ImageRef` and `FontRef` are thread-affine convenience wrappers. If another thread needs ownership, send the ID and create/retain a new wrapper there.
- [ ] Add shared/atomic managed refs later only if callers need owned refs to cross thread boundaries.
- [ ] Use `send` for clear/reset/retain/release messages so important cache-control events are not dropped.
- [ ] Reserve `push` only for future lossy update-style messages.
- [ ] Keep generation state in `imgutils` behind a lock for phase 1, because uploads can be produced before the render thread sees them.
- [ ] Do not clear `fontTable`, `typefaceTable`, or `typefaceSourceTable` in the first implementation.
- [ ] Full atlas reset clears image and glyph atlas entries; visible user images must be reloaded by application logic.
- [ ] Text glyphs are allowed to regenerate automatically after atlas reset.

## Thread-Safety Principles

- [ ] Treat integer/hash IDs as the safe cross-thread resource handles.
- [ ] Do not pass renderer/backend contexts across threads for cache mutation.
- [ ] Do not mutate GPU resources or atlas tables outside the render thread.
- [ ] Destructors must never touch backend state directly.
- [ ] Use channels to move all image payloads and cache-control requests to the render thread.
- [ ] Keep cache generation state protected by a lock or owned by the render-thread message processor.
- [ ] Prefer explicit message ordering over ad hoc direct calls.

## Unified Image Channel

- [ ] Replace `RChan[ImgObj]` with an internal message channel:

  ```nim
  type ImageMsgKind = enum
    imkPutFlippy
    imkPutPixie
    imkClearImage
    imkClearImages
    imkClearImageCache
    imkRetainImage
    imkReleaseImage
    imkClearFontGlyphs
    imkClearTypefaceGlyphs
    imkRetainFont
    imkReleaseFont
  ```

- [ ] Define one message type for uploads, clears, and refcount transitions:

  ```nim
  type ImageMsg = object
    generation: uint64
    ownerToken: uint64
    imageId: ImageId
    fontId: FontId
    typefaceId: TypefaceId
    imageIds: seq[ImageId]
    case kind: ImageMsgKind
    of imkPutFlippy:
      flippy: Flippy
    of imkPutPixie:
      image: Image
    else:
      discard
  ```

- [ ] Keep `ImgObj` as a compatibility/internal upload payload only if that reduces churn; otherwise replace it with `ImageMsg`.
- [ ] Move or isolate image payloads when sending `imkPutFlippy` or `imkPutPixie`.
- [ ] Keep clear/retain/release messages ID-only so they are cheap and naturally thread-safe.
- [ ] Drain image messages at the start of `renderRoot` or `renderFrame`.
- [ ] Process messages in channel order.
- [ ] Use `send` for important cache commands and consider `push` only for explicitly lossy update-style messages.

## Manual Cache APIs

- [ ] Add logical image clearing that is safe from any thread:

  ```nim
  proc clearImage*(id: ImageId)
  proc clearImages*(ids: openArray[ImageId])
  ```

- [ ] Implement these procs by updating logical cache generation state and sending `imkClearImage` or `imkClearImages`.
- [ ] Add renderer convenience APIs that still enqueue messages instead of mutating backend state directly:

  ```nim
  proc clearImage*[BackendState](renderer: FigRenderer[BackendState], id: ImageId)
  proc clearImages*[BackendState](
    renderer: FigRenderer[BackendState], ids: openArray[ImageId]
  )
  ```

- [ ] Add full atlas/cache reset:

  ```nim
  proc clearImageCache*[BackendState](renderer: FigRenderer[BackendState])
  ```

- [ ] Implement full reset by sending `imkClearImageCache`.
- [ ] Document that `clearImage(id)` makes an image reloadable and removes atlas lookup state, but does not reclaim packed atlas holes.
- [ ] Document that `clearImageCache(renderer)` is the memory relief path because it resets/recreates atlas storage.

## Stale Upload Protection

- [ ] Maintain a generation for each `ImageId`.
- [ ] Stamp every upload message with the generation observed when the image was loaded.
- [ ] Increment an image generation when `clearImage(id)` is requested.
- [ ] Increment a global cache generation when `clearImageCache(renderer)` is requested.
- [ ] Skip `imkPutFlippy` and `imkPutPixie` messages whose generation is stale.
- [ ] Let an explicit clear win over older in-flight uploads.
- [ ] Consider allowing a newer upload for the same `ImageId` after clear by stamping it with the new generation.

## Render-Thread Processing

- [ ] On `imkPutFlippy` or `imkPutPixie`, upload to the backend atlas if the message generation is current.
- [ ] On `imkClearImage`, remove the image from backend entries and atlas metadata.
- [ ] On `imkClearImages`, remove each listed image.
- [ ] On `imkClearImageCache`, reset the whole atlas and clear logical image/glyph cached state.
- [ ] On `imkClearFontGlyphs`, remove glyph atlas entries for the font.
- [ ] On `imkClearTypefaceGlyphs`, remove glyph atlas entries for fonts using that typeface.
- [ ] On retain/release messages, update render-thread ownership tables used by the managed-handle layer.

## Atlas Metadata

- [ ] Add metadata beside backend atlas entries:

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

- [ ] Mark user-loaded images as `aekImage`.
- [ ] Mark generated glyph images as `aekGlyph`.
- [ ] Mark shape/shadow/corner generated assets as `aekGenerated`.
- [ ] Use metadata so image clears do not remove glyphs or generated renderer assets.
- [ ] Use metadata so font clears only remove glyph entries.

## Backend Atlas Operations

- [ ] Add backend methods:

  ```nim
  method removeImage*(ctx: BackendContext, id: ImageId) {.base.}
  method clearImageAtlas*(ctx: BackendContext) {.base.}
  method clearFontGlyphs*(ctx: BackendContext, fontId: FontId) {.base.}
  method clearTypefaceGlyphs*(ctx: BackendContext, typefaceId: TypefaceId) {.base.}
  ```

- [ ] Implement for OpenGL, Metal, and Vulkan.
- [ ] `removeImage` should delete lookup/metadata entries; it does not reclaim skyline holes.
- [ ] `clearImageAtlas` should flush pending draw batches before resetting backend atlas state.
- [ ] Reset atlas texture to the initial size.
- [ ] Clear backend `entries`.
- [ ] Clear backend atlas metadata.
- [ ] Reset skyline `heights`.
- [ ] For Vulkan, recreate or mark atlas GPU storage dirty as appropriate.
- [ ] Bump global cache generation during full reset.

## Managed Handle Layer

- [ ] Keep managed handles additive and ID-based:

  ```nim
  type
    ImageRef* = object
      id*: ImageId

    FontRef* = object
      font*: FigFont
      fontId*: FontId
  ```

- [ ] Avoid making `ImageRef` or `FontRef` the only way to use images/fonts.
- [ ] Document that managed refs are thread-affine.
- [ ] Document that raw IDs are the supported way to communicate resources across threads.
- [ ] Maintain thread-local counts for cheap same-thread copies.
- [ ] Allocate one stable `ownerToken` per thread.
- [ ] On first local `ImageRef` retain for an ID, send `imkRetainImage(id, ownerToken)`.
- [ ] On last local `ImageRef` release for an ID, send `imkReleaseImage(id, ownerToken)`.
- [ ] On first local `FontRef` retain for a font, send `imkRetainFont(fontId, ownerToken)`.
- [ ] On last local `FontRef` release for a font, send `imkReleaseFont(fontId, ownerToken)`.
- [ ] The render thread should aggregate owner tokens per ID and clear only when the aggregate owner set is empty.
- [ ] A final release should be an automatic eviction hint, not a direct forced clear from a destructor.
- [ ] Manual `clearImage(id)` remains a force-clear request.
- [ ] Do not automatically remove `typefaceTable` or `typefaceSourceTable` in the first version.

## Managed Constructors

- [ ] Add image constructors:

  ```nim
  proc loadImageRef*(path: string): ImageRef
  proc imageRef*(id: ImageId, image: Image): ImageRef
  ```

- [ ] Add font constructors:

  ```nim
  proc fontRef*(font: FigFont): FontRef
  proc fontRef*(typefaceId: TypefaceId, size: float32): FontRef
  ```

- [ ] `loadImageRef(path)` should call the normal load path and return the ID wrapper.
- [ ] `imageRef(id, image)` should upload through the image message channel and retain the ID.
- [ ] `fontRef` should retain the `FontId` derived from the `FigFont`.

## Ownership Hook Rules

- [ ] Keep destructors non-raising.
- [ ] Destructors should only update thread-local counts and enqueue retain/release messages.
- [ ] Do not mutate backend context, GPU resources, global image sets, or atlas tables from `=destroy`.
- [ ] Declare custom hooks immediately after managed-handle type definitions.
- [ ] Test copy, move, destroy-after-move, self-assignment, and final-release behavior.
- [ ] Verify hooks with `--expandArc` before relying on destructor behavior.

## Streaming Folder Workflow

- [ ] App keeps a visible image set plus a preload margin.
- [ ] App stores `ImageId`s in UI nodes and may optionally hold `ImageRef`s for visible/preloaded images.
- [ ] App drops refs or calls `clearImage(id)` when images scroll out of range.
- [ ] Final `ImageRef` release sends a release message; the render thread clears only when no owner tokens remain.
- [ ] App calls `clearImageCache(renderer)` when atlas size or memory budget crosses a threshold.
- [ ] After a full cache reset, app reloads currently visible/preloaded image IDs.

## Phased Rollout

- [ ] Phase 1: add `ImageMsg`, compatibility wrappers, generation tracking, and manual `clearImage`.
- [ ] Phase 1: keep existing upload behavior working through wrappers.
- [ ] Phase 1: add stale queued upload tests.
- [ ] Phase 2: add backend `removeImage`, `clearImageAtlas`, and `clearImageCache(renderer)`.
- [ ] Phase 2: add atlas reset tests for image and text redraw.
- [ ] Phase 3: add atlas metadata and targeted font/glyph clears.
- [ ] Phase 3: add tests proving image clears do not delete glyph/generated entries.
- [ ] Phase 4: add `ImageRef` and `FontRef` thread-affine managed wrappers.
- [ ] Phase 4: add ownership hook and owner-token aggregation tests.
- [ ] Phase 5: add docs/examples for streaming folders and memory-budget reset policy.

## Tests

- [ ] `clearImage(id)` sends a clear message and increments the image generation.
- [ ] `clearImage(id)` allows `loadImage(path)` to enqueue a newer upload.
- [ ] Stale queued uploads are skipped after `clearImage(id)`.
- [ ] `imkClearImage` removes the backend atlas entry.
- [ ] Drawing a cleared image does not crash.
- [ ] `imkClearImageCache` resets atlas entries and logical image markers.
- [ ] Text redraw regenerates glyphs after a full atlas reset.
- [ ] `imkClearFontGlyphs` removes only glyph entries for that font.
- [ ] `ImageRef` first retain sends `imkRetainImage`.
- [ ] `ImageRef` final release sends `imkReleaseImage`.
- [ ] Releases from one thread do not clear an image still retained by another thread.
- [ ] Passing raw `ImageId` across threads and creating a new `ImageRef` on the target thread retains under that thread's owner token.
- [ ] Moving or sharing `ImageRef` across threads is documented as unsupported in phase 4.
- [ ] `FontRef` final release sends `imkReleaseFont`.
- [ ] Manual `clearImage(id)` overrides retained state by design.

## Implementation Order

- [ ] Implement phase 1.
- [ ] Run focused image tests.
- [ ] Implement phase 2.
- [ ] Run focused render/image/text tests.
- [ ] Implement phase 3.
- [ ] Run focused font/glyph tests.
- [ ] Implement phase 4.
- [ ] Run ownership hook tests under ARC/ORC.
- [ ] Implement phase 5.
- [ ] Run `nim test`.
