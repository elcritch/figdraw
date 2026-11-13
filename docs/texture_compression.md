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
