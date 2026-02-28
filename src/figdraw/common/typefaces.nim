import std/isolation
import std/os
import std/strutils
import std/locks
import std/math

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./rchannels
import ./imgutils
import ./fonttypes
import ./shared
import ../extras/systemfonts

type TypeFaceKinds* = enum
  TTF
  OTF
  SVG

var
  typefaceTable*: Table[TypefaceId, Typeface] ## holds the table of parsed fonts
  fontTable*: Table[FontId, FigFont]
  staticTypefaceTable*:
    Table[string, tuple[name: string, data: string, kind: TypeFaceKinds]]
  fontLock*: Lock

fontLock.initLock()

proc normalizeTypefaceLookupName(name: string): string =
  name.toLowerAscii()

proc lookupTypefaceNames(name: string): seq[string] =
  result.add(name.normalizeTypefaceLookupName())
  let fileName = extractFilename(name)
  if fileName.len > 0:
    result.add(fileName.normalizeTypefaceLookupName())
  let stem = splitFile(name).name
  if stem.len > 0:
    result.add(stem.normalizeTypefaceLookupName())
  let fileStem = splitFile(fileName).name
  if fileStem.len > 0:
    result.add(fileStem.normalizeTypefaceLookupName())

proc registerStaticTypefaceData(name, data: string, kind: TypeFaceKinds) =
  ## Registers a static typeface blob that can be found by loadTypeface.
  let entry = (name: name, data: data, kind: kind)
  for key in lookupTypefaceNames(name):
    staticTypefaceTable[key] = entry

template registerStaticTypeface*(
    name: static[string], path: static[string], kind: static[TypeFaceKinds] = TTF
) =
  ## Registers a static typeface by reading the font file at compile-time.
  const fontData {.gensym.} = staticRead(path)
  registerStaticTypefaceData(name, fontData, kind)

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

proc loadTypeface*(name: string, fallbackNames: openArray[string] = []): FontId =
  ## loads a font from a file and adds it to the font index

  proc resolveTypefacePath(name: string): string =
    let dataPath = figDataDir() / name
    if fileExists(dataPath):
      info "resolved typeface from figDataDir", requested = name, path = dataPath
      return dataPath

    if fileExists(name):
      info "resolved typeface from direct path", requested = name, path = name
      return name

    let stem = splitFile(name).name
    let systemPath = findSystemFontFile([name, stem])
    if systemPath.len > 0:
      info "resolved typeface from system fonts", requested = name, path = systemPath
      return systemPath

    warn "unable to resolve typeface path", requested = name, figDataDir = figDataDir()
    result = ""

  var candidateNames = @[name]
  candidateNames.add(fallbackNames)

  var loaded = false
  var typeface: Typeface
  for candidate in candidateNames:
    let typefacePath = resolveTypefacePath(candidate)
    if typefacePath.len > 0:
      try:
        typeface = readTypeface(typefacePath)
        loaded = true
        break
      except PixieError:
        warn "failed to read resolved typeface path",
          requested = name, candidate = candidate, path = typefacePath

    for key in lookupTypefaceNames(candidate):
      if key in staticTypefaceTable:
        let staticEntry = staticTypefaceTable[key]
        try:
          info "resolved typeface from static registry",
            requested = name, candidate = candidate, staticName = staticEntry.name
          typeface =
            readTypefaceImpl(staticEntry.name, staticEntry.data, staticEntry.kind)
          loaded = true
          break
        except PixieError:
          warn "failed to read static registered typeface",
            requested = name, candidate = candidate, staticName = staticEntry.name
    if loaded:
      break

  if not loaded:
    raise newException(
      PixieError,
      "Unable to resolve typeface '" & name & "' with fallback names: " & $fallbackNames,
    )

  let id = typeface.getId()

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

proc pixieFont(font: FigFont): (FontId, Font) =
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

proc convertFont*(font: FigFont): (FontId, Font) =
  ## does the typesetting using pixie, then converts to Figuro's internal
  ## types

  result = font.pixieFont()
  if not fontTable.hasKey(result[0]):
    fontTable[result[0]] = font

proc convertFont*(style: FontStyle): (FontId, Font) =
  style.font.convertFont()

proc glyphFontFor*(uiFont: FigFont): tuple[id: FontId, font: Font, glyph: GlyphFont] =
  ## Get the GlyphFont
  let (fontId, pf) = uiFont.convertFont()
  let defaultLineHeight = pf.defaultLineHeight()
  let lineHeight = if pf.lineHeight >= 0: pf.lineHeight else: defaultLineHeight
  let lineGap = (lineHeight / pf.scale) - pf.typeface.ascent + pf.typeface.descent
  let baselineOffset = round((pf.typeface.ascent + lineGap / 2) * pf.scale)
  result = (
    id: fontId,
    font: pf,
    glyph: GlyphFont(fontId: fontId, lineHeight: lineHeight, descentAdj: baselineOffset),
  )

proc getLineHeightImpl*(font: FigFont): float32 =
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
  var uifont: FigFont
  withLock(fontLock):
    uifont = fontTable[fontId]
  result = uifont.pixieFont()[1]
  result.size = result.size.getScaledFont()
  #result.size = result.size
  result.lineHeight = result.lineHeight.scaled()
