import std/[hashes, unicode]
import uimaths

export uimaths

import pkg/chroma
export chroma

type
  TypefaceId* = Hash
  FontId* = Hash
  GlyphId* = Hash
  FontName* = string

  FontCase* = enum
    NormalCase
    UpperCase
    LowerCase
    TitleCase

  FontHorizontal* = enum
    Left
    Center
    Right

  FontVertical* = enum
    Top
    Middle
    Bottom

  GlyphOrigin* = enum
    GlyphTopLeft
    GlyphBaseline

  GlyphFont* = object
    fontId*: FontId
    size*: float32 ## Font size in pixels.
    lineHeight*: float32
    descentAdj*: float32
      ## The line height in pixels or autoLineHeight for the font's default line height.

  UiFont* = object
    typefaceId*: TypefaceId
    size*: float32 = 12.0'f32 ## Font size in pixels.
    lineHeight*: float32 ## The line height in pixels
    lineHeightDefault*: float32
    fontCase*: FontCase
    underline*: bool ## Apply an underline.
    strikethrough*: bool ## Apply a strikethrough.
    noKerningAdjustments*: bool ## Optionally disable kerning pair adjustments

  FontStyle* = object
    font*: UiFont
    color*: Color

  GlyphArrangement* = object
    contentHash*: Hash
    lines*: seq[Slice[int]] ## The (start, stop) of the lines of text.
    spans*: seq[Slice[int]] ## The (start, stop) of the spans in the text.
    fonts*: seq[GlyphFont] ## The font for each span.
    spanColors*: seq[Color] ## The color for each span.
    runes*: seq[Rune] ## The runes of the text.
    positions*: seq[Vec2] ## The positions of the glyphs for each rune.
    selectionRects*: seq[Rect] ## The selection rects for each glyph.
    maxSize*: Vec2
    minSize*: Vec2
    bounding*: Rect

proc hash*(fnt: UiFont): Hash =
  var h = Hash(0)
  for n, f in fnt.fieldPairs():
    when n != "paints":
      h = h !& hash(f)
  result = !$h

proc hash*(style: FontStyle): Hash =
  var h = Hash(0)
  h = h !& hash(style.font)
  h = h !& hash(style.color)
  result = !$h

proc fs*(font: UiFont, color: Color = color(0, 0, 0, 1)): FontStyle =
  ## helper for making font style objects
  FontStyle(font: font, color: color)

proc fsp*(font: UiFont, color: Color, text: string): (FontStyle, string) =
  ## helper for making font span objects
  (FontStyle(font: font, color: color), text)

proc getId*(font: UiFont): FontId =
  FontId font.hash()

proc fontWithSize*(fontId: TypeFaceId, size: float32): UiFont =
  UiFont(typefaceId: fontId, size: size)

proc getContentHash*(
    size: Vec2,
    uiSpans: openArray[(FontStyle, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
): Hash =
  var h = Hash(0)
  h = h !& hash(size)
  h = h !& hash(uiSpans)
  h = h !& hash(hAlign)
  h = h !& hash(vAlign)
  result = !$h

proc getContentHash*(
    size: Vec2,
    uiSpans: openArray[(UiFont, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
): Hash =
  var styled = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (font, text) in uiSpans:
    styled.add((fs(font), text))
  result = getContentHash(size, styled, hAlign, vAlign)
