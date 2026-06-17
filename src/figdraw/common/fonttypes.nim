import std/[hashes, unicode]
import uimaths
import filltypes

export uimaths
export filltypes

import pkg/chroma
export chroma

type
  TypefaceId* = distinct Hash
  FontId* = distinct Hash
  GlyphId* = distinct Hash
  FontGlyphId* = distinct uint32
  FontName* = distinct string

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

  FigFont* = object
    typefaceId*: TypefaceId
    size*: float32 = 12.0'f32 ## Font size in pixels.
    lineHeight*: float32 ## The line height in pixels
    lineHeightDefault*: float32
    fontCase*: FontCase
    underline*: bool ## Apply an underline.
    strikethrough*: bool ## Apply a strikethrough.
    noKerningAdjustments*: bool ## Optionally disable kerning pair adjustments

  FontStyle* = object
    font*: FigFont
    color*: Fill

  GlyphSourceRange* = object
    byteStart*: int ## Inclusive source byte index.
    byteEnd*: int ## Exclusive source byte index.
    runeStart*: int ## Inclusive index into GlyphArrangement.sourceRunes.
    runeEnd*: int ## Exclusive index into GlyphArrangement.sourceRunes.

  ArrangedGlyph* = object
    fontId*: FontId
    glyphId*: FontGlyphId
    cluster*: uint32
    source*: GlyphSourceRange
    rune*: Rune ## Cheap first/source rune for compatibility and diagnostics.
    isWhitespace*: bool
    pos*: Vec2
    advance*: Vec2
    offset*: Vec2
    rect*: Rect

  GlyphArrangement* = object
    contentHash*: Hash
    lines*: seq[Slice[int]] ## The (start, stop) of the lines of text.
    spans*: seq[Slice[int]] ## The (start, stop) of the spans in the text.
    fonts*: seq[GlyphFont] ## The font for each span.
    spanColors*: seq[Fill] ## The fill for each span.
    sourceRunes*: seq[Rune] ## The decoded source runes for glyph source ranges.
    arrangedGlyphs*: seq[ArrangedGlyph] ## Glyph-id-first placement data.
    runes*: seq[Rune] ## The runes of the text.
    positions*: seq[Vec2] ## The positions of the glyphs for each rune.
    selectionRects*: seq[Rect] ## The selection rects for each glyph.
    maxSize*: Vec2
    minSize*: Vec2
    bounding*: Rect

const figdrawTextBackend* {.strdefine.} = "pixie"

static:
  doAssert figdrawTextBackend in ["pixie", "harfbuzzy", "hybrid"]

proc hash*(id: TypefaceId): Hash {.borrow.}
proc `==`*(a, b: TypefaceId): bool {.borrow.}

proc hash*(id: FontId): Hash {.borrow.}
proc `==`*(a, b: FontId): bool {.borrow.}

proc hash*(id: GlyphId): Hash {.borrow.}
proc `==`*(a, b: GlyphId): bool {.borrow.}

proc hash*(id: FontGlyphId): Hash {.borrow.}
proc `==`*(a, b: FontGlyphId): bool {.borrow.}
proc `$`*(id: FontGlyphId): string {.borrow.}

proc hash*(name: FontName): Hash {.borrow.}
proc `==`*(a, b: FontName): bool {.borrow.}
proc `$`*(name: FontName): string {.borrow.}

func syntheticFontGlyphId*(fontId: FontId, rune: Rune): FontGlyphId {.inline.} =
  ## Returns the Pixie-compatible synthetic glyph id for a source rune.
  ## The id is interpreted together with fontId by render/cache code.
  discard fontId
  FontGlyphId(rune.uint32)

func sourceRune*(arrangement: GlyphArrangement, glyphIndex: int): Rune {.inline.} =
  ## Returns the cheap representative source rune for a glyph.
  if arrangement.arrangedGlyphs.len > 0:
    arrangement.arrangedGlyphs[glyphIndex].rune
  else:
    arrangement.runes[glyphIndex]

func sourceRuneRange*(
    arrangement: GlyphArrangement, glyphIndex: int
): Slice[int] {.inline.} =
  ## Returns the inclusive source-rune range for a glyph.
  let source =
    if arrangement.arrangedGlyphs.len > 0:
      arrangement.arrangedGlyphs[glyphIndex].source
    else:
      GlyphSourceRange(runeStart: glyphIndex, runeEnd: glyphIndex + 1)
  result = source.runeStart .. source.runeEnd - 1

iterator sourceRunes*(arrangement: GlyphArrangement, glyphIndex: int): Rune =
  ## Iterates the source runes mapped to a glyph.
  let sourceRange = arrangement.sourceRuneRange(glyphIndex)
  if sourceRange.a <= sourceRange.b:
    if arrangement.sourceRunes.len > 0:
      for i in sourceRange:
        yield arrangement.sourceRunes[i]
    else:
      for i in sourceRange:
        yield arrangement.runes[i]

proc hash*(fnt: FigFont): Hash =
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

proc fs*(font: FigFont, color: Fill = fill(rgba(0, 0, 0, 255))): FontStyle =
  ## helper for making font style objects
  FontStyle(font: font, color: color)

proc fsp*(font: FigFont, color: Fill, text: string): (FontStyle, string) =
  ## helper for making font span objects
  (FontStyle(font: font, color: color), text)

proc span*(font: FigFont, color: Fill, text: string): (FontStyle, string) =
  ## helper for making font span objects
  (FontStyle(font: font, color: color), text)

proc getId*(font: FigFont): FontId =
  FontId font.hash()

proc fontWithSize*(fontId: TypeFaceId, size: float32): FigFont =
  FigFont(typefaceId: fontId, size: size)

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
    uiSpans: openArray[(FigFont, string)],
    hAlign = FontHorizontal.Left,
    vAlign = FontVertical.Top,
): Hash =
  var styled = newSeqOfCap[(FontStyle, string)](uiSpans.len)
  for (font, text) in uiSpans:
    styled.add((fs(font), text))
  result = getContentHash(size, styled, hAlign, vAlign)
