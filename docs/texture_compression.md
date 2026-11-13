# GPU texture compression

This work adds explicit BC3 compression for ordinary color images. It keeps the
existing RGBA atlas for dynamic UI content, glyphs, and distance fields. Native
compressed images use separate textures, with batch boundaries preserving draw
order. Unsupported devices decode the same payload into the normal RGBA path.

## Format decision

| Technique | Fit for FigDraw |
| --- | --- |
| PNG, Snappy, Zstandard | Reduce stored/transferred bytes, but decode to full-size GPU textures. The existing Flippy format already uses Snappy. |
| BC3 / DXT5 | 16 bytes per 4×4 RGBA block, including independent alpha. A compact CPU codec and broad desktop API support make it a practical initial opt-in format. |
| BC7 | Also 16 bytes per 4×4 block, with more flexible color coding. Attractive for offline assets, but a substantially more involved encoder than BC3. |
| ASTC | Flexible block sizes and useful Apple/mobile coverage. Needs an additional encoder and capability-dependent asset selection. |
| ETC2 / EAC | Useful GLES/mobile formats, but a separate encoder and platform path would be required. |
| KTX2 / Basis Universal | A container/transcoding pipeline that can target BCn, ASTC, and ETC formats. Suitable for a future offline asset pipeline; it introduces a transcoder dependency and more than the current runtime image API needs. |
| R8 coverage or distance textures | A separate lossless channel-reduction opportunity. It is not block compression and must preserve each shader's channel semantics. |

BC3 reduces a block-aligned RGBA8 image's payload by 4×. Small or odd-sized
images pay for complete blocks, so use
`ceil(width / 4) * ceil(height / 4) * 16`, not simply `width * height`, to estimate
compressed bytes. The format is lossy: it is appropriate only when the caller
accepts color and alpha approximation. Never automatically compress MSDF/MTSDF,
glyph masks, or other numeric textures; errors in those textures change edges.

The payload uses linear UNORM sampling and straight RGBA, matching the existing
GPU image upload convention. Pixie's premultiplied pixels are converted before
encoding and restored when the CPU fallback decodes them. The first version
supports a single 2D mip level; it does not add DDS/KTX loading or automatic
mipmap generation.

## Capability and ownership rules

- Metal checks native BC texture support; OpenGL checks S3TC support; Vulkan
  checks and enables the device feature and validates the format capabilities.
- A capability query reports native compressed residency, not whether the
  fallback can accept a compressed payload.
- The image handle/message pipeline retains compressed bytes and replays them
  to new renderers. Each renderer chooses its own native or decoded storage.
- Separate resources must survive submitted work, and replacement in either
  direction must remove stale state. Compressed storage is counted separately
  from atlas occupancy.
- Texture payload sizes, atlas allocations, and process RSS are different
  measurements. A separate compressed texture does not shrink an atlas already
  allocated for other UI content, and switching textures can add draw batches.

## API and limits

`compressImage(pixieImage)` returns a validated `CompressedImage` containing
BC3 blocks. `imageRef(id, compressed)` publishes it through the ordinary retained
image lifecycle; `loadCompressedImage(id, compressed)` is the manually managed
variant. `decompressImage(compressed)` provides a portable Pixie reference.
Malformed dimensions and payload lengths raise `ValueError` before upload.

Use `supportsTextureCompression(tcfBc3)` on the renderer's backend context to
query native storage. `compressedTextureBytes()` counts BC3 payload bytes and
`compressedTextureCount()` counts standalone native textures; both are zero for
decoded fallback storage. These queries belong on the rendering thread. The
OpenGL query needs a current context. Metal currently uses a conservative
8192-pixel limit per compressed texture dimension; OpenGL and Vulkan validate
their device limits. The initial implementation emits a batch boundary around
each compressed image draw. Public APIs are for the ordinary source renderer,
not an addition to the separately staged native-dynlib ABI.

## Tiger measurement

Measured on Apple M3 Pro / macOS 15.7.9, Nim 2.2.12 release ORC, native Metal BC3.
The example rasterizes the same SVG through Pixie first, then either uploads
RGBA or compresses that raster. It does **not** compress SVG distance fields.
Frame sizes include a 16-pixel border; image sizes are 480×480 and 992×992.
Encoding times are medians of three process runs, excluding SVG rasterization.

| Frame | RGBA payload | BC3 payload | RGBA atlas | BC3 atlas + separate texture | Encode |
| --- | ---: | ---: | ---: | ---: | ---: |
| 512² | 900 KiB | 225 KiB | 1 MiB | 16 KiB + 225 KiB | 14.3 ms |
| 1024² | 3,844 KiB | 961 KiB | 4 MiB | 16 KiB + 961 KiB | 77.2 ms |

Both modes start with a 64² atlas to expose the incremental image allocation.
These are texture payload/allocation figures, not total process or GPU memory;
render targets, buffers, driver padding, and retained CPU copies are excluded.
An application starting with a 2048² atlas keeps that allocation in either mode.
The 512² captures have mean RGB-channel absolute differences of approximately
1.5–1.8 on the 0–255 scale; gradients and fine color boundaries can visibly change.
This is an opt-in memory/quality tradeoff, not a lossless replacement.

```sh
nim c -d:release --mm:orc examples/compressed_images.nim
./examples/compressed_images rgba 512 rgba.png
./examples/compressed_images bc3 512 bc3.png
./examples/compressed_images rgba 1024 rgba-large.png
./examples/compressed_images bc3 1024 bc3-large.png
```

The program prints native support, actual compressed byte/count totals, atlas
size, and encoding time. A fallback run reports zero native compressed bytes.

## Sources

- [Microsoft block compression overview](https://learn.microsoft.com/en-us/windows/uwp/graphics-concepts/block-compression)
  describes BC3 storage and alpha/color encoding.
- [Khronos data format specification](https://registry.khronos.org/DataFormat/specs/1.4/dataformat.1.4.html)
  defines compressed block layouts.
- [Khronos KTX developer guide](https://github.com/KhronosGroup/3D-Formats-Guidelines/blob/main/KTXDeveloperGuide.md)
  compares transmission formats and native transcode targets.
- [Apple Metal feature tables](https://developer.apple.com/metal/Metal-Feature-Set-Tables.pdf)
  document format support across GPU families.
- [OpenGL S3TC specification](https://registry.khronos.org/OpenGL/extensions/EXT/EXT_texture_compression_s3tc.txt)
  defines compressed texture upload formats.
- [Vulkan compressed-format guide](https://docs.vulkan.org/guide/latest/formats.html)
  explains the feature checks used for BC formats.
