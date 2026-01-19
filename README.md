# FigDraw

`figdraw` is a Nim rendering library for building and rendering 2D scene graphs
(`Fig` nodes) with a focus on:

- A thread-safe renderer pipeline (render tree construction and preparation can be done off the main thread; OpenGL submission stays on the GL thread).
- An OpenGL backend with SDF (signed-distance-field) primitives for crisp rounded-rect rendering and gaussian based shadows.
- Font and text support with layout and thread-safe primitives.

![RGB boxes render](tests/expected/render_rgb_boxes.png)

## Status

This repo is actively evolving. The OpenGL backend is the primary
implementation (`src/figdraw/opengl/`).

## Requirements

- Nim `>= 2.0.10` (ARC/ORC-based memory managers; required by `src/figdraw/common/rchannels.nim`)
- OpenGL (desktop GL by default; GLES/emscripten shader paths via `-d:useOpenGlEs` and/or `-d:emscripten`)
- Dependencies are managed by Atlas (see `nim.cfg` and `deps/`), though should work with Nimble

## Quick Start

Dependencies are managed via Atlas (not Nimble). Atlas generates `nim.cfg` and
populates `deps/`.

```sh
# Try the repo:
git clone https://github.com/elcritch/figdraw
cd figdraw
atlas install --feature:windy --feature:sdl2

# Run an example:
nim r examples/opengl_windy_renderlist.nim
```

```sh
# Use as a dependency (in your own project):
atlas use https://github.com/elcritch/figdraw
atlas install
```

## Using Library

The most stable entry points today are:

- Core types/utilities: `import figdraw/commons`
- Scene graph nodes: `import figdraw/fignodes`
- OpenGL backend: `import figdraw/opengl/renderer`

For a complete working example (window + GL context + render loop), see:

- `examples/opengl_windy_renderlist.nim`
- `examples/sdl2_renderlist.nim`

## Run Tests

Runs all tests + compiles all examples listed in `config.nims`:

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
nim r examples/opengl_windy_renderlist.nim
```

Notes:

- The main OpenGL shader combines atlas sampling and SDF rendering, switching per-draw via an `sdfMode` attribute (no shader swaps for SDF vs atlas).
- Masks still use a separate mask shader program.
- Current SDF modes include clip/AA fills, annular (outline) modes, and drop/inset shadow modes used by the renderer when `-d:useSdf` is enabled.

## Useful Defines

- `-d:figdraw.names=true`: enables `Fig.name` for debugging (enabled for tests in `tests/config.nims`)
- `-d:useOpenGlEs`: select GLES/emscripten shader sources when GLSL 3.30 is not available
- `-d:openglMajor=3 -d:openglMinor=3`: override the requested OpenGL version (see `src/figdraw/utils/glutils.nim`)

## Thread Safety Notes

- Rendering is structured so that preparing render lists/trees can be done off-thread.
- GPU resource submission (OpenGL calls) must happen on the GL thread; the backend enforces this separation.

## License

See `LICENSE`.
