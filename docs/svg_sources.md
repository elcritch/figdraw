# SVG source history

The SVG modules were imported and adapted from Merenda commit
`7979567ca1d9739bf38c9b74c8b8b6c0d15293a2` (the local `main` checkout when imported):

- `src/figdraw/svgs/svgpathloader.nim` from
  `src/merenda/nimkit/drawing/svgpathloader.nim`.
- `src/figdraw/svgs/svgimages.nim` from
  `src/merenda/nimkit/drawing/svgimages.nim`.
- `src/figdraw/svgs/svg.nim` from the SVG helpers in
  `src/merenda/nimkit/drawing/drawing.nim`.

The imported SVG drawing code from Merenda and SDFy is covered by FigDraw's
[MIT license](../LICENSE), with Jaremy Creechley's copyright recorded there.
Adaptations replace NimKit geometry, DrawContext, and image resources with
FigDraw's geometry, RenderList, and ImageRef APIs. Tests are adapted from
Merenda's SVG tests. The original path loader was adapted from
`sdfy/src/sdfy/msdfgenSvg.nim`.

The bundled `data/Ghostscript_Tiger.svg` was copied unchanged from
Merenda's `examples/Ghostscript_Tiger.svg` at the same revision.
