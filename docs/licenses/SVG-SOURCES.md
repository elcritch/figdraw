# SVG source notices

The SVG modules were imported and adapted from Merenda commit
`7979567ca1d9739bf38c9b74c8b8b6c0d15293a2` (the local `main` checkout when imported):

- `src/figdraw/svgs/svgpathloader.nim` from
  `src/merenda/nimkit/drawing/svgpathloader.nim`.
- `src/figdraw/svgs/svgimages.nim` from
  `src/merenda/nimkit/drawing/svgimages.nim`.
- `src/figdraw/svgs/svg.nim` from the SVG helpers in
  `src/merenda/nimkit/drawing/drawing.nim`.

Merenda is Copyright (c) 2026, Jaremy Creechley, under the
[BSD 3-Clause License](MERENDA.txt). Adaptations replace NimKit geometry,
DrawContext, and image resources with FigDraw's geometry, RenderList, and
ImageRef APIs. Tests are adapted from Merenda's SVG tests.
The bundled `data/Ghostscript_Tiger.svg` was copied unchanged from
Merenda's `examples/Ghostscript_Tiger.svg` at the same revision.

The path loader carries an Apache-2.0 SPDX notice and identifies
`sdfy/src/sdfy/msdfgenSvg.nim` as its original source. The
[Apache 2.0 license](APACHE-2.0.txt) is included here to preserve that notice.
Sdfy's distributed [license notice](SDFY.txt) is also retained.
The loader includes Pixie's SVG implementation from the installed dependency;
Pixie's own license remains applicable to that code.
