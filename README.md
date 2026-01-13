# FigDraw

`figdraw` is a Nim rendering library for building and rendering 2D scene graphs (`Fig` nodes) with a focus on:

- A thread-safe renderer pipeline (render tree construction and preparation can be done off the main thread; OpenGL submission stays on the GL thread).
- A Shady-powered OpenGL backend with optional SDF (signed-distance-field) primitives for crisp rounded-rect rendering and gaussian based shadows.

![RGB boxes render](tests/expected/render_rgb_boxes.png)

## Status

This repo is actively evolving. The OpenGL backend is the primary implementation (`src/figdraw/opengl/`).

## Requirements

- Nim (this project expects ARC/ORC; `config.nims` and `tests/config.nims`)
- OpenGL (desktop GL, or GLES via `-d:useOpenGlEs` / emscripten paths)

## Using Library

This project uses Atlas-managed deps in `deps/`.

```sh
atlas use https://github.com/elcritch/figdraw.git
```

## Run Tests

Runs all tests under `tests/`:

```sh
nim test
```

Run a single test:

```sh
nim r tests/trender_rgb_boxes.nim
```

## SDF Rendering (`-d:useSdf`)

The OpenGL backend supports rendering rounded rectangles using an SDF shader path. This is enabled in the renderer with:

```sh
nim r -d:useSdf example/opengl_windex_renderlist.nim
```

Notes:

- The main OpenGL shader combines atlas sampling and SDF rendering, switching per-draw via an `sdfMode` attribute (no shader swaps for SDF vs atlas).
- Masks still use a separate mask shader program.
- Current SDF modes include clip/AA fills, annular (outline) modes, and drop/inset shadow modes used by the renderer when `-d:useSdf` is enabled.

## Thread Safety Notes

- Rendering is structured so that preparing render lists/trees can be done off-thread.
- GPU resource submission (OpenGL calls) must happen on the GL thread; the backend enforces this separation.

## License

See `LICENSE`.
