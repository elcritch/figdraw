# FigDraw

`figdraw` is a *pure* Nim rendering library for building and rendering 2D scene graphs (`Fig` nodes) with a focus on being small and easy to use.

Features:

- GPU Rendering with OpenGL / Metal / Vulkan!
- Rects & shadows default to SDF (signed-distance-field) primitives for crisp, dynamic, and low memory UI primitives
- Lightweight, multiplatform, and high performance by design! (few or no allocations for each frame)
- Thread-safe renderer pipeline. (render tree construction and preparation can be done off the main thread)
- Modern and fast text rendering and layout using [Pixie](https://github.com/treeform/pixie/) with thread-safe Text API.
- Image rendering using a texture atlas.
- Supports layering and multiple "roots" per layer - great for menus, overlays, etc.
- SDF/MSDF (Multi-SDF) based glyph rendering.
- Linear gradients with 2 and 3 stop points.
- Fast Gaussian 2-pass node operation for fast background blurs.
- Clipping and layering support. 

## Quick Start

This part works best with a recent Atlas (>= 0.9.6) version:

```sh
# Try the repo:
git clone https://github.com/elcritch/figdraw
cd figdraw
atlas install --feature:windy --feature:sdl2

# Run an example:
nim c -r examples/windy_renderlist.nim
```

```sh
# Use as a dependency (in your own project):
atlas use https://github.com/elcritch/figdraw
```

Alternatively Nimble should work as well:
```sh
nimble install https://github.com/elcritch/figdraw
```

**NOTE**: If you get errors you may need to install a newer version of Nimble or Atlas that support "features".

### Install / Usage Notes

**IMPORTANT**: to use features like windy, you'll want to add it to requires:

```nim
requires "https://github.com/elcritch/figdraw[windy]"
```

Alternatively, you can just `atlas use windy`.

## Programs Built with FigDraw

- [Neonim](https://github.com/elcritch/neonim) - cross platform GUI backend for Neovim.

## What's It Look Like?

Here's the primary rounded rect primitive with corners, borders, and shadows:

<img width="800" height="600" alt="render_rgb_boxes_sdf" src="https://github.com/user-attachments/assets/6a7ef1f5-92de-4c0b-a1f5-29d8500afdd4" />

Here's it running as an overlay on top of a 3D scene:

<img width="1012" height="781" alt="Screenshot 2026-02-20 at 12 56 09 AM" src="https://github.com/user-attachments/assets/73a0eb3d-23f0-471c-bf61-1f35fa0946ed" />


Here's text rendering curtesy of Pixie. Note that Pixie's layout can be used or custom layout, e.g. for monospaced renderers:

<img width="1012" height="740" alt="Screenshot 2026-02-20 at 12 58 46 AM" src="https://github.com/user-attachments/assets/10de11d1-c528-4c25-9afd-38d282ecd800" />


Here's a video example (unfortunately capped at 30fps) of real time shadows, borders, and corners chaning fluidly at 120 FPS:

https://github.com/user-attachments/assets/aca4783c-86c6-4e52-9a16-0a8556ad1300

## Status

This repo is still under development but the core support for SDF is running! 
OpenGL backend is the only supported renderer right now
(`src/figdraw/opengl/`). However there's some work toward supporting Vulkan.

Future directions may include adding support for SDF textures for text rendering using Valve's SDF-text mapping technique. Other directions in that area would be supporting vector images rasterized to SDF textures as well. 

The next big item is hopefully setting up some examples of doing WebGL version with Windy.

Finally there will be a C API and a setup to compile FigDraw as a shared library. 

## Requirements

- Nim `>= 2.0.10` (ARC/ORC-based memory managers; required by `src/figdraw/common/rchannels.nim`)
- OpenGL (desktop GL by default; GLES/emscripten shader paths via `-d:useOpenGlEs` and/or `-d:emscripten`)

## Using Library

The most stable entry points today are:

- Core types/utilities: `import figdraw/commons`
- Scene graph nodes: `import figdraw/fignodes`
- OpenGL backend: `import figdraw/figrender`

Render list example (build a small scene tree):

```nim
import figdraw/commons
import figdraw/fignodes
import chroma

proc makeRenders(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 255),
  ))

  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    screenBox: rect(80, 60, 240, 140),
    fill: rgba(220, 40, 40, 255),
    corners: [12.0'f32, 12.0, 12.0, 12.0],
    stroke: RenderStroke(weight: 3.0, fill: rgba(0, 0, 0, 255)),
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list
```

Feed the resulting `Renders` into the OpenGL backend; see the examples below for a full render loop.

For a complete working example (window + GL context + render loop), see:

- `examples/windy_renderlist.nim`
- `examples/sdl2_renderlist.nim`

## Gradients (Fill API)

FigDraw uses `Fill` everywhere a color-style value is needed:

- `Fig.fill`
- `RenderStroke.fill`
- `RenderShadow.fill`
- text span styles (`fs` / `span`)

API:

- Solid fill: `fill(rgba(...))`
- Linear 2-stop: `linear(start, stop, axis = fgaX|fgaY|fgaDiagTLBR|fgaDiagBLTR)`
- Linear 3-stop: `linear(start, mid, stop, axis = ..., midPos = 128'u8)`

`midPos` is `0..255` and controls where the middle stop lands along the gradient axis.
`ColorRGBA` values (like `rgba(...)`) are accepted directly where `Fill` is expected.

Example (box + stroke + text span gradient):

```nim
import figdraw/commons
import figdraw/fignodes
import chroma

proc makeGradientDemo(w, h: float32, uiFont: FigFont): Renders =
  var list = RenderList()

  let panelFill = linear(
    rgba(255, 236, 168, 255),
    rgba(255, 178, 116, 255),
    axis = fgaY,
  )
  let strokeFill = linear(
    rgba(255, 120, 66, 255),
    rgba(72, 197, 255, 255),
    axis = fgaDiagTLBR,
  )
  let titleFill = linear(
    rgba(255, 120, 66, 255),
    rgba(252, 220, 128, 255),
    rgba(72, 197, 255, 255),
    axis = fgaX,
    midPos = 96'u8,
  )

  let root = list.addRoot(Fig(
    kind: nkRectangle,
    screenBox: rect(0, 0, w, h),
    fill: rgba(245, 245, 245, 255),
  ))

  discard list.addChild(root, Fig(
    kind: nkRectangle,
    screenBox: rect(40, 40, 360, 180),
    fill: panelFill,
    corners: [14.0'f32, 14.0, 14.0, 14.0],
    stroke: RenderStroke(weight: 3.0, fill: strokeFill),
  ))

  let titleLayout = typeset(
    rect(0, 0, 320, 50),
    [
      span(uiFont, rgba(20, 20, 20, 255), "FigDraw "),
      span(uiFont, titleFill, "OpenGL"),
    ],
    wrap = false,
  )

  discard list.addChild(root, Fig(
    kind: nkText,
    screenBox: rect(60, 70, 320, 50),
    textLayout: titleLayout,
    # For nkText: glyph colors come from span fills. `fill` is used for selection highlight.
    fill: rgba(255, 235, 170, 255),
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list
```

## Layers and ZLevel

`Renders` is an ordered table of `ZLevel -> RenderList`. Lower zlevels are drawn first, so higher
zlevels appear on top. Each layer can contain multiple roots (useful for overlays, HUDs, menus, etc).

Short example:

```nim
import figdraw/commons
import figdraw/fignodes
import chroma

proc makeRenders(w, h: float32): Renders =
  var bg = RenderList()
  discard bg.addRoot(Fig(
    kind: nkRectangle,
    screenBox: rect(0, 0, w, h),
    fill: rgba(245, 245, 245, 255),
  ))

  var overlay = RenderList()
  discard overlay.addRoot(Fig(
    kind: nkRectangle,
    zlevel: 10.ZLevel,
    screenBox: rect(40, 40, 220, 120),
    fill: rgba(43, 159, 234, 255),
    corners: [10.0'f32, 10.0, 10.0, 10.0],
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = bg
  result.layers[10.ZLevel] = overlay
  result.layers.sort(proc(x, y: auto): int = cmp(x[0], y[0]))
```

## MSDF Bitmap based SDF Rendering

This has many benefits over regular textures for rendering vector shapes. It acts as a sort of "compression" technique allow us to scale the size of the shape while maintaining sharp edges with small texture sizes. Generally 64x64 can scale up to a fullscreen object with reasonable quality.

The other benefit is being able to draw shadows / strokes / etc similar to regular SDFs! See the blue stroked start below using the same SDF glyph as the others:

<img width="1136" height="780" alt="Screenshot 2026-02-03 at 5 56 30 PM" src="https://github.com/user-attachments/assets/728e7b59-d8db-4408-bc50-637742237022" />


See [examples/windy_msdf_star.nim](examples/windy_msdf_star.nim) for more info.

## Run Tests

Runs all tests + compiles all examples listed in `config.nims`:

```sh
nim test
```

Run a single test:

```sh
nim r tests/trender_rgb_boxes.nim
```

## SDF Rendering (default)

The OpenGL backend renders rounded rectangles and shadows using an SDF shader
path by default:

```sh
nim r examples/windy_renderlist.nim
```

To force the older texture path, compile with `-d:useFigDrawTextures`.

Notes:

- The main OpenGL shader combines atlas sampling and SDF rendering, switching per-draw via an `sdfMode` attribute (no shader swaps for SDF vs atlas).
- Masks still use a separate mask shader program.
- Current SDF modes include clip/AA fills, annular (outline) modes, and drop/inset shadow modes used by the renderer.

## Useful Defines

- `-d:figdraw.names=true`: enables `Fig.name` for debugging (enabled for tests in `tests/config.nims`)
- `-d:useOpenGlEs`: select GLES/emscripten shader sources when GLSL 3.30 is not available
- `-d:useFigDrawTextures`: force the legacy texture-based shape rendering path (disables SDF shapes)
- `-d:openglMajor=3 -d:openglMinor=3`: override the requested OpenGL version (see `src/figdraw/utils/glutils.nim`)

## Thread Safety Notes

- Rendering is structured so that preparing render lists/trees can be done off-thread.
- GPU resource submission (OpenGL calls) must happen on the GL thread; the backend enforces this separation.

## License

See `LICENSE`.
