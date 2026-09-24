# Render-data ownership

FigDraw render data has an acyclic ownership contract under ARC and ORC.
Only the recursive `RenderFragment` and diagnostic `RenderTree` types need
explicit `{.acyclic.}` annotations. Nim already infers acyclicity for `Fig`,
`RenderList`, `Renders`, `RenderFragments`, and the glyph/text payload types.
The annotation records an ownership contract; it does not break cycles or make
mutable objects safe to share concurrently.

| Type | Owning references and invariant |
| --- | --- |
| `Fig`, `RenderList`, `Renders` | Own drawing values and text payloads. `Fig.parent` is an integer index; nodes never retain their owner. |
| `RenderFragment` | Owns descendant fragments only. It has no parent or tree reference. |
| `RenderFragments` | Owns base lists and downward fragment edges. It never stores handles or cursors. |
| `RenderFragmentHandle`, `RenderCursor` | Retain the tree and fragment for safe invalidation checks. Nothing in that tree retains them. |
| `Utf8Runes`, `GlyphArrangement` | UTF-8 storage contains only bytes/checkpoints. Glyph views retain an immutable complete arrangement; that arrangement cannot itself be a view. |
| `GlyphPosition` | Contains only glyph geometry values. |
| `RenderTree` | Diagnostic output with downward child references. Callers must not insert the tree itself or an ancestor into its public `children` sequence. |

`moveFragment` rejects both self-attachment and attachment beneath a descendant
before mutating the graph. Its attachment records contain a parent reference only
temporarily while moving an edge; fragments do not retain those records.

Transfer exclusive ownership through an isolated channel payload and release
producer-side aliases before handoff. Acyclic annotations do not make reference
counts atomic. `FontRef` and `ImageRef` remain thread-affine managed leases;
transfer their IDs and establish ownership on the receiving thread instead.

## Renderer ownership is separate

This contract does not cover `FigRenderer`, backend contexts, or native windows.
An owning window reference formed a real cycle when a callback stored on that
window captured the renderer:

```text
renderer -> backendState.window -> onRender closure -> renderer
```

The Siwin backend and its OpenGL fallback state now borrow their window using
`{.cursor.}`, removing the renderer-to-window owning edge. The caller must keep
the window alive through rendering and renderer cleanup. This is a borrow, not
a weak reference that automatically becomes nil when the window is destroyed.
Other window shims and custom backend states retain their existing contracts.

`finishPendingFrames` waits for submitted GPU work on the renderer's owning
thread: Metal waits for its last submitted command buffer, Vulkan waits for the
device, and OpenGL finishes the current context. Call it after the final frame
and before releasing the renderer or its native presentation target. Custom
asynchronous backend contexts must override the operation.

The renderer's `contextActivation` procedure uses `nimcall` and has no captured
closure environment. It does not introduce that cycle.

Siwin's `useDedicatedRenderThread` already clears the window reference before a
handoff. However, clearing that reference and moving the object does not itself
remove an earlier registration in the creating thread's ORC cycle-candidate
buffer. After releasing producer-side aliases and assembling an exclusively
owned, isolated renderer payload, the sender must retire those registrations
with `GC_runOrc()` before publishing the payload to another thread. Sigils
`RChan` can do this with `-d:nimSafeOrcSend`; Merenda instead performs the
collection only for renderer commands, avoiding collections for each acyclic
frame snapshot. Render-data annotations alone do not fix renderer handoff.

## Verification

The ownership regression exercises sixteen exclusive transfers of previously
aliased fragment trees, render lists, diagnostic trees, and shared glyph views.
The fragment suite verifies that cycle-forming moves fail without changing
handles or topology. The Siwin callback regression verifies immediate context
destruction when the owning window leaves scope.

```sh
atlas-run tests renderownership renderfragments siwin_dedicated_render -- --mm:orc
atlas-run tests renderownership renderfragments siwin_dedicated_render -- --mm:arc
```

For sanitizer coverage, use Clang with malloc-backed Nim allocation and pass the
sanitizers to both compilation and linking:

```sh
UBSAN_OPTIONS=halt_on_error=1 atlas-run tests renderownership -- \
  --mm:orc --cc:clang -d:useMalloc -d:noSignalHandler --debugger:native \
  --passC:'-fsanitize=address,undefined -fno-omit-frame-pointer' \
  --passL:'-fsanitize=address,undefined'
```
