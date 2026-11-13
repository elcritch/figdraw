# SVG memory benchmark: Ghostscript tiger

For this fixed-size tiger, a single Pixie CPU raster used less memory and was
much faster to prepare than FigDraw's adaptive layered SVG representation.
The layered representation retains ordered drawing layers, GPU primitives,
distance fields, and thin-stroke coverage images; those benefits come with a
higher cost in this test.

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
