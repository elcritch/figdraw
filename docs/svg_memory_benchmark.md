# SVG memory benchmark: Ghostscript tiger

A single flattened tiger raster is cheapest for a fixed image. For independently
animated paints, the comparison changes: the table below also measures one
cropped raster per fill or stroke against reusable small MTSDF layers and GPU
primitives at different display sizes.

Measured on macOS 15.7.9, Apple M3 Pro (arm64), Nim 2.2.12, release build with
ORC, using the Metal offscreen renderer. Each frame has a 16-pixel margin, so
the tiger occupies 480×480 or 992×992 pixels. Values below are medians of
three independent process runs except image payload, which comes from a
separate instrumentation run. MiB means 1,048,576 bytes.

| Frame | Method | Peak RSS | Image payload | Final atlas | Preparation |
| --- | --- | ---: | ---: | ---: | ---: |
| 512×512 | Layered adaptive MTSDF + primitives | 48.1 MiB | 6.81 MiB (298 images) | 16 MiB | 1,686 ms |
| 512×512 | Pixie whole-SVG raster | 25.8 MiB | 0.88 MiB (1 image) | 16 MiB | 6.3 ms |
| 1024×1024 | Layered adaptive MTSDF + primitives | 114.9 MiB | 19.49 MiB (291 images) | 64 MiB | 1,696 ms |
| 1024×1024 | Pixie whole-SVG raster | 50.9 MiB | 3.75 MiB (1 image) | 16 MiB | 11.5 ms |

Peak RSS is the maximum resident memory for the entire process, including the
renderer, screenshot readback, 20 warm frames, and platform driver accounting;
it is not a direct measurement of GPU memory. Payload is the sum of width ×
height × 4 for image messages, including coverage images. Its subscription
copies images, so payload runs are separate from the RSS trials. Atlas size is
its final edge squared × 4 bytes, excluding buffers and render targets; it is
not total GPU allocation. These measures overlap and should not be added.
Preparation covers parsing and resource/scene construction, before renderer
setup and the first frame.

The raster is cached at the measured target size: preserving its resolution
when zooming requires rerasterization. Layered rendering can reuse geometry and
distance fields, but may allocate and retain additional coverage tiers as the
target grows. The implementations have different SVG parser semantics, so this
is a workload comparison rather than a claim of identical output or a general
result for every SVG.

## Independently drawn paints and scaling

The previous table uses **one flattened raster**. This second benchmark keeps
all 304 visible fill and stroke paints as independently drawn, tightly cropped
RGBA images, with a two-pixel transparent border around each paint. It renders
at the requested display resolution. The MTSDF approach uses the same SVG
loader as the viewer, with an initial document long-edge budget of 96 or 192
texels. Both use a 2048² starting atlas and a white background. The raster
baseline uses the same parsed paths and stroke outlines, and retains separate
images so paints can be moved or changed independently. The tiger contains no
gradients, masks, or opacity groups; this baseline rejects those effects rather
than estimating their cost.

Measured on the same Apple M3 Pro / macOS 15.7.9 system, with Nim 2.2.12,
release ORC, and Metal. Display sizes below are the tiger itself, without the
16-pixel frame margin used in the earlier table. Times and RSS are medians of
three separate process runs; payload counts come from separate instrumented
runs. Preparation includes parsing, creating fields or per-paint rasters,
constructing the render list, and creating any thin-stroke coverage images.

| Display | Representation | Image payload | Peak RSS | Final atlas | Prepare | Warm frame |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 480² | MTSDF budget 96 | 5.30 MiB (298 images) | 44.3 MiB | 16 MiB | 612 ms | 0.21 ms |
| 480² | MTSDF budget 192 | 6.81 MiB (298 images) | 49.5 MiB | 16 MiB | 1,708 ms | 0.31 ms |
| 480² | Cropped per-paint raster | 6.52 MiB (304 images) | 44.5 MiB | 16 MiB | 18 ms | 0.40 ms |
| 992² | MTSDF budget 96 | 17.98 MiB (291 images) | 108.4 MiB | 64 MiB | 636 ms | 0.62 ms |
| 992² | MTSDF budget 192 | 19.49 MiB (291 images) | 118.1 MiB | 64 MiB | 1,876 ms | 0.56 ms |
| 992² | Cropped per-paint raster | 26.55 MiB (304 images) | 146.6 MiB | 64 MiB | 28 ms | 0.49 ms |

Warm frame is the elapsed time for 20 submissions divided by 20, including a
final GPU completion wait; it excludes resource preparation, presentation,
and screenshot readback. These short timings are machine-specific and should
not be read as a stable FPS or animation-throughput comparison. Peak RSS includes
renderer setup, readback, and those frames. Payload and atlas allocation overlap
with RSS and must not be added to it. Payload measurement copies images in a
separate run, so it is not used for RSS. Neither payload nor atlas reports total
GPU memory; they exclude buffers, transient render targets, and driver overhead.

The 96 budget reduces payload by about 19% at 480² and 32% at 992² compared
with cropped per-paint rasters. It takes substantially longer to build. It is
also visibly less accurate: against the per-paint raster capture, its mean
absolute RGB difference was 2.76/255 at 480² and 2.62/255 at 992², versus
1.40 and 1.16 for the 192 budget. This raster is a comparison image, not a
standards-conformance reference; antialiasing and sampling differences also
contribute. The budgets are not hard maximum sizes for every texture: adaptive
fields may use up to 4× the base scale, and thin-stroke coverage images are
created at target-dependent resolution. Those coverage images explain why even
the small-budget payload increases substantially at 992².

For a zoom from 480² to 992² and back, a retained MTSDF resource can reuse its
fields and geometry, though it may generate and retain new coverage tiers as
sizes change. A per-paint raster cache can likewise scale its existing images
without rerasterizing, trading sharpness for reuse; maintaining native-resolution
rasters at both sizes requires generating and retaining two sets, or regenerating
when the target changes. The independent measurements above show the costs at
each endpoint, **not a measured continuous animation or a sum of cache
allocations**. Moving an unchanged paint can reuse either representation. If a
path's geometry changes, its field or raster must be regenerated; this benchmark
does not measure selective updates, continuous scaling, or long-running cache
growth. A flat raster can also be transformed cheaply, but cannot independently
animate its paints.

Reproduce the per-paint comparison on macOS/Metal:

```sh
nim c -d:release --mm:orc examples/svg_layer_memory_bench.nim
/usr/bin/time -l ./examples/svg_layer_memory_bench mtsdf 480 96
/usr/bin/time -l ./examples/svg_layer_memory_bench mtsdf 480 192
/usr/bin/time -l ./examples/svg_layer_memory_bench raster 480 192
/usr/bin/time -l ./examples/svg_layer_memory_bench mtsdf 992 96
/usr/bin/time -l ./examples/svg_layer_memory_bench mtsdf 992 192
/usr/bin/time -l ./examples/svg_layer_memory_bench raster 992 192
# Repeat each with `payload` as a fourth argument for image counts and bytes.
```

The harness also writes captures to `tests/output/layer-bench-*.png` for visual
comparison. Each invocation creates a fresh resource and renderer.

To reproduce on macOS with the Metal backend, from the repository root:

```sh
nim c -d:release --mm:orc examples/svg_memory_bench.nim
/usr/bin/time -l ./examples/svg_memory_bench layered 512
/usr/bin/time -l ./examples/svg_memory_bench raster 512
/usr/bin/time -l ./examples/svg_memory_bench layered 1024
/usr/bin/time -l ./examples/svg_memory_bench raster 1024
# Run separately for image payload counts; do not use these runs for peak RSS.
./examples/svg_memory_bench layered 512 payload
./examples/svg_memory_bench raster 512 payload
./examples/svg_memory_bench layered 1024 payload
./examples/svg_memory_bench raster 1024 payload
```

The benchmark reads `data/Ghostscript_Tiger.svg`, starts with a 2048×2048
atlas, and writes screenshots to `tests/output/`.
