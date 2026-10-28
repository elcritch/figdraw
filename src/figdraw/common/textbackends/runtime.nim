## Runtime dispatch between the compiled Pixie and HarfBuzzy backends.

import std/unicode
import ../fonttypes
import ../typefaces
import pkg/pixie/fonts
import ./pixie as pixieBackend
import ./harfbuzzy as harfbuzzyBackend

proc typeset*(
    box: Rect,
    spans: openArray[(FontStyle, string)],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap, rasterize: bool,
): GlyphArrangement =
  case selectedTextBackend()
  of TextBackendKind.Pixie:
    pixieBackend.typeset(box, spans, hAlign, vAlign, minContent, wrap, rasterize)
  of TextBackendKind.Harfbuzzy, TextBackendKind.Hybrid:
    harfbuzzyBackend.typeset(box, spans, hAlign, vAlign, minContent, wrap, rasterize)
  of TextBackendKind.Uirelays:
    raise newException(ValueError, "UIRelays requires a uirelays text build")

proc typesetSourceSpans*(
    box: Rect,
    source: Utf8Runes,
    runs: openArray[StyledTextRun],
    styles: openArray[FontStyle],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    minContent, wrap, rasterize: bool,
): GlyphArrangement =
  case selectedTextBackend()
  of TextBackendKind.Pixie:
    pixieBackend.typesetSourceSpans(
      box, source, runs, styles, hAlign, vAlign, minContent, wrap, rasterize
    )
  of TextBackendKind.Harfbuzzy, TextBackendKind.Hybrid:
    harfbuzzyBackend.typesetSourceSpans(
      box, source, runs, styles, hAlign, vAlign, minContent, wrap, rasterize
    )
  of TextBackendKind.Uirelays:
    raise newException(ValueError, "UIRelays requires a uirelays text build")

proc resolvePlacedGlyph*(
    font: FigFont, rune: Rune
): tuple[
  glyphFont: GlyphFont,
  glyphId: FontGlyphId,
  advance: float32,
  imageOffset: Vec2,
  skipsRaster: bool,
] =
  if selectedTextBackend() == TextBackendKind.Pixie:
    let info = glyphFontFor(font)
    result = (
      info.glyph,
      syntheticFontGlyphId(info.glyph.fontId, rune),
      info.font.typeface.getAdvance(rune) * info.font.scale,
      vec2(0, 0),
      rune.isWhiteSpace,
    )
  else:
    result = harfbuzzyBackend.resolvePlacedGlyph(font, rune)
