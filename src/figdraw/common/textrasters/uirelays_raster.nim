## One-rune native rasterization into FigDraw's GPU glyph atlas.

import std/unicode
import pkg/pixie
from pkg/uirelays/screen as relays import nil
import ../[fonttypes, imgutils, typefaces]
import ./uirelays_fonts
export uirelays_fonts

when defined(windows):
  import pkg/uirelays/drivers/winapi_driver
  initUirelaysFontProvider(winapiFontRelays())
else:
  {.error: "the uirelays text backend currently requires Windows".}

proc renderUirelaysGlyph*(
    imageId: ImageId, fontId: FontId, rune: Rune, upload = true
): Image {.discardable.} =
  var pixels: seq[uint32]
  let extent = renderRelayGlyph(fontId, $rune, pixels)
  if extent.w <= 0 or extent.h <= 0:
    return nil
  result = newImage(extent.w, extent.h)
  for i, p in pixels:
    result.data[i] = rgbx(
      uint8((p shr 16) and 0xFF),
      uint8((p shr 8) and 0xFF),
      uint8(p and 0xFF),
      uint8(p shr 24),
    )
  if upload:
    loadGlyphImage(imageId, fontId, getFigFont(fontId).typefaceId, result)
