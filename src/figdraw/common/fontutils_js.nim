import fonttypes
import uimaths

type TypeFaceKinds* = enum
  TTF
  OTF
  SVG

type Box* = Rect

proc getTypefaceImpl*(name: string): FontId =
  FontId(0)

proc getTypefaceImpl*(name, data: string, kind: TypeFaceKinds): FontId =
  FontId(0)

proc getLineHeightImpl*(font: UiFont): float32 =
  0.0

proc getTypesetImpl*(
    box: Box,
    spans: openArray[(UiFont, string)],
    hAlign = Left,
    vAlign = Top,
    minContent = false,
    wrap = true,
): GlyphArrangement =
  GlyphArrangement()
