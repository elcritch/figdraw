import std/isolation
import std/os
import std/strutils
import std/locks

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./rchannels
import ./imgutils
import ./fonttypes
import ./shared

var
  typefaceTable*: Table[TypefaceId, Typeface] ## holds the table of parsed fonts
  fontTable*: Table[FontId, UiFont]
  fontLock*: Lock

fontLock.initLock()

type TypeFaceKinds* = enum
  TTF
  OTF
  SVG

proc hash*(tp: Typeface): Hash =
  var h = Hash(0)
  h = h !& hash tp.filePath
  result = !$h

proc getId*(typeface: Typeface): TypefaceId =
  result = TypefaceId typeface.hash()
  for i in 1 .. 100:
    if result.int == 0:
      result = TypefaceId(typeface.hash() !& hash(i))
    else:
      break
  doAssert result.int != 0, "Typeface hash results in invalid id"

proc readTypefaceImpl(
    name, data: string, kind: TypeFaceKinds
): Typeface {.raises: [PixieError].} =
  ## Loads a typeface from a buffer
  try:
    result =
      case kind
      of TTF:
        parseTtf(data)
      of OTF:
        parseOtf(data)
      of SVG:
        parseSvgFont(data)
  except IOError as e:
    raise newException(PixieError, e.msg, e)

  result.filePath = name

proc loadTypeface*(name: string): FontId =
  ## loads a font from a file and adds it to the font index

  let
    typefacePath = figDataDir() / name
    typeface = readTypeface(typefacePath)
    id = typeface.getId()

  doAssert id != 0
  if id in typefaceTable:
    doAssert typefaceTable[id] == typeface
  typefaceTable[id] = typeface
  result = id

proc loadTypeface*(name, data: string, kind: TypeFaceKinds): FontId =
  ## loads a font from buffer and adds it to the font index

  let
    typeface = readTypefaceImpl(name, data, kind)
    id = typeface.getId()

  typefaceTable[id] = typeface
  result = id

proc pixieFont(font: UiFont): (FontId, Font) =
  let
    id = FontId(hash((font.getId(), figUiScale())))
    typeface = typefaceTable[font.typefaceId]

  var pxfont = newFont(typeface)
  pxfont.size = font.size
  pxfont.typeface = typeface
  pxfont.textCase = parseEnum[TextCase]($font.fontCase)
  pxfont.lineHeight = font.lineHeight
  pxfont.underline = font.underline
  pxfont.strikethrough = font.strikethrough
  pxfont.noKerningAdjustments = font.noKerningAdjustments

  if font.lineHeight == 0.0'f32:
    pxfont.lineHeight = pxfont.defaultLineHeight()
  result = (id, pxfont)

proc convertFont*(font: UiFont): (FontId, Font) =
  ## does the typesetting using pixie, then converts to Figuro's internal
  ## types

  result = font.pixieFont()
  if not fontTable.hasKey(result[0]):
    fontTable[result[0]] = font

proc convertFont*(style: FontStyle): (FontId, Font) =
  style.font.convertFont()

proc glyphFontFor*(uiFont: UiFont): tuple[id: FontId, font: Font, glyph: GlyphFont] =
  ## Get the GlyphFont
  let (fontId, pf) = uiFont.convertFont()
  let defaultLineHeight = pf.defaultLineHeight()
  let lineHeight = if pf.lineHeight >= 0: pf.lineHeight else: defaultLineHeight
  let lhAdj = 0.0'f32
  result = (
    id: fontId,
    font: pf,
    glyph: GlyphFont(fontId: fontId, lineHeight: lineHeight, descentAdj: lhAdj),
  )

proc getLineHeightImpl*(font: UiFont): float32 =
  let (_, pf) = font.convertFont()
  result = pf.lineHeight

proc snapFontSizeDown(size: float): float32 =
  let sizes = [8'f32, 12, 16, 24, 32, 48, 64, 96, 128]
  for i in countdown(sizes.len - 1, 0):
    if size >= float(sizes[i]):
      return sizes[i]
  return sizes[0]

proc getScaledFont*(size: float32): float32 =
  result = size.scaled()

proc getPixieFont*(fontId: FontId): Font =
  var uifont: UiFont
  withLock(fontLock):
    uifont = fontTable[fontId]
  result = uifont.pixieFont()[1]
  result.size = result.size.getScaledFont()
  #result.size = result.size
  result.lineHeight = result.lineHeight.scaled()
