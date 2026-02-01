import std/[os, unicode, sequtils, tables, strutils, sets, hashes]
import std/isolation

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./rchannels
import ./imgutils
import ./shared

import ./fonttypes
import ./typefaces

type GlyphPosition* = ref object ## Represents a glyph position after typesetting.
  fontId*: FontId
  rune*: Rune
  pos*: Vec2 # Where to draw the image character.
  rect*: Rect
  descent*: float32
  lineHeight*: float32

proc hash*(glyph: GlyphPosition): Hash {.inline.} =
  #result = hash((2344, glyph.fontId, glyph.rune, app.uiScale))
  result = hash((2344, glyph.fontId, glyph.rune))

proc generateGlyph*(glyph: GlyphPosition) =
  if unicode.isWhiteSpace(glyph.rune):
    return

  let hashFill = glyph.hash()

  if not hasImage(hashFill.ImageId):
    let
      fontId = glyph.fontId
      font = getPixieFont(fontId)

    let
      text = $glyph.rune
      arrangement = pixie.typeset(
        @[newSpan(text, font)],
        bounds = glyph.rect.wh.scaled(),
        hAlign = CenterAlign,
        vAlign = TopAlign,
        wrap = false,
      )
    let
      snappedBounds = arrangement.computeBounds().scaled().snapToPixels()

    let
      lh = font.defaultLineHeight()
      bounds = rect(0, 0, snappedBounds.w + snappedBounds.x, scaled(lh))

    if bounds.w == 0 or bounds.h == 0:
      error "GEN IMG: ", rune = $glyph.rune, wh = repr wh, snapped = repr snappedBounds
      return

    try:
      font.paint = parseHex"FFFFFF"
      var image = newImage(bounds.w.int, bounds.h.int)
      image.fillText(arrangement)

      # put into cache
      loadImage(hashFill.ImageId, image)
    except PixieError:
      discard

iterator glyphs*(arrangement: GlyphArrangement): GlyphPosition =
  var idx = 0

  block:
    for i, (span, gfont) in zip(arrangement.spans, arrangement.fonts):
      while idx < arrangement.runes.len():
        let
          pos = arrangement.positions[idx]
          rune = arrangement.runes[idx]
          selection = arrangement.selectionRects[idx]

        #let descent = gfont.lineHeight - gfont.descentAdj
        let descent = gfont.lineHeight

        yield GlyphPosition(
          fontId: gfont.fontId,
          rune: rune,
          pos: pos,
          rect: selection,
          descent: descent,
          lineHeight: gfont.lineHeight,
        )

        idx.inc()
        if idx notin span:
          break

proc generateGlyphImages*(arrangement: GlyphArrangement) =
  ## returns Glyph's hash, will generate glyph if needed
  ##
  ## Font Glyphs are generated with Bottom vAlign and Center hAlign
  ## this puts the glyphs in the right position
  ## so that the renderer doesn't need to figure out adjustments

  for glyph in arrangement.glyphs():
    glyph.generateGlyph()

proc convertArrangement*(
    arrangement: Arrangement,
    box: Rect,
    uiSpans: openArray[(UiFont, string)],
    hAlign: FontHorizontal,
    vAlign: FontVertical,
    gfonts: seq[GlyphFont],
): GlyphArrangement =
  var
    lines = newSeqOfCap[Slice[int]](arrangement.lines.len())
    spanSlices = newSeqOfCap[Slice[int]](arrangement.spans.len())
    selectionRects = newSeqOfCap[Rect](arrangement.selectionRects.len())
  for line in arrangement.lines:
    lines.add line[0] .. line[1]
  for span in arrangement.spans:
    spanSlices.add span[0] .. span[1]
  for rect in arrangement.selectionRects:
    selectionRects.add rect

  result = GlyphArrangement(
    contentHash:
      block:
        var h = Hash(0)
        h = h !& getContentHash(box.wh, uiSpans, hAlign, vAlign)
        h = h !& hash(app.uiScale)
        !$h,
    lines: lines,
    spans: spanSlices,
    fonts: gfonts,
    runes: arrangement.runes,
    positions: arrangement.positions,
    selectionRects: selectionRects,
  )

