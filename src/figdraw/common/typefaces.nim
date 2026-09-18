import std/os
import std/strutils
import std/locks
import std/math
import std/options
import std/tables
import std/unicode

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
import pkg/chronicles

import ./imgutils
import ./fonttypes
import ./shared
import ./typefaceinfos
import ../extras/systemfonts

export
  SystemTypefaceFile, SystemTypeface, TypefaceInfo, TypefaceLocalizedName,
  TypefaceVariationAxis

type TypeFaceKinds* = enum
  TTF
  OTF
  SVG

type TypefaceSource* = object
  name*: string
  data*: string
  kind*: TypeFaceKinds
  faceIndex*: int

type
  ResolvedTypefacePath = object
    path: string
    faceIndex: int

  FontRefHandle = object
    value: FigFont
    id: FontId

  ## Thread-affine managed font handle.
  ##
  ## Pass raw FontId or FigFont values across threads and create a new FontRef on
  ## the receiving thread when that thread needs ownership.
  FontRef* = ref FontRefHandle

var
  typefaceTable* {.threadvar.}: Table[TypefaceId, Typeface]
    ## Per-thread cache of parsed fonts.
  fontTable*: Table[FontId, FigFont]
  typefaceSourceTable*: Table[TypefaceId, TypefaceSource]
  typefaceInfoTable: Table[TypefaceId, TypefaceInfo]
  staticTypefaceTable*:
    Table[string, tuple[name: string, data: string, kind: TypeFaceKinds]]
  fontLock*: Lock
  fontUiScaleTable: Table[FontId, float32]

fontLock.initLock()

proc resetFontCache*(clearStaticTypefaces: bool) =
  ## Clears registered typefaces, metadata, fonts, and their cached glyph images.
  ## Also clears the calling thread's parsed-typeface cache. Other threads keep
  ## their local parsed caches until they exit.
  ## Call only while font work and rendering are idle and old FontRef handles
  ## have been released. Reload typefaces before using their IDs or fonts again.
  ## Static typeface registrations are preserved unless explicitly requested.
  var typefaceIds: seq[TypefaceId]
  {.cast(gcsafe).}:
    withLock(fontLock):
      for id in typefaceSourceTable.keys:
        typefaceIds.add(id)
      typefaceTable.clear()
      fontTable.clear()
      fontUiScaleTable.clear()
      typefaceSourceTable.clear()
      typefaceInfoTable.clear()
      if clearStaticTypefaces:
        staticTypefaceTable.clear()
  for id in typefaceIds:
    clearTypefaceGlyphs(id)

proc resetFontCache*() =
  ## Clears font caches while preserving static typeface registrations.
  ## Has the same lifetime and threading requirements as the bool overload.
  resetFontCache(clearStaticTypefaces = false)

proc hasTypeface*(id: TypefaceId): bool =
  ## Whether a typeface is registered in the current font cache.
  {.cast(gcsafe).}:
    withLock(fontLock):
      result = id in typefaceSourceTable

proc hasFont*(id: FontId): bool =
  ## Whether a raster font is registered in the current font cache.
  {.cast(gcsafe).}:
    withLock(fontLock):
      result = id in fontTable

proc `=destroy`(fontRef: var FontRefHandle) =
  releaseFontRefId(fontRef.id)
  `=destroy`(fontRef.value)

func font*(fontRef: FontRef): lent FigFont {.inline.} =
  ## The font owned by this handle.
  fontRef.value

func fontId*(fontRef: FontRef): FontId {.inline.} =
  ## The registered font ID owned by this handle.
  fontRef.id

proc isNil*(fontRef: FontRef): bool =
  ## Whether the font handle is empty.
  system.isNil(fontRef)

proc sameFontRef*(a, b: FontRef): bool =
  ## Whether two font handles retain the same ownership object.
  a == b

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

proc registerStaticTypefaceData*(name, data: string, kind: TypeFaceKinds) =
  ## Registers a static typeface blob that can be found by loadTypeface.
  let entry = (name: name, data: data, kind: kind)
  withLock(fontLock):
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
    if Hash(result).int == 0:
      result = TypefaceId(typeface.hash() !& hash(i))
    else:
      break
  doAssert Hash(result).int != 0, "Typeface hash results in invalid id"

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

proc typefaceKindFromPath(path: string): TypeFaceKinds =
  case splitFile(path).ext.toLowerAscii()
  of ".otf", ".otc": OTF
  of ".svg": SVG
  else: TTF

proc isTypefaceCollection(path: string): bool =
  splitFile(path).ext.toLowerAscii() in [".ttc", ".otc"]

proc readTypefacePath(
    path, requestedName: string, requestedFaceIndex = -1
): tuple[typeface: Typeface, source: TypefaceSource] {.raises: [PixieError].} =
  if path.isTypefaceCollection():
    let typefaces = readTypefaces(path)
    if typefaces.len == 0:
      raise newException(PixieError, "typeface collection is empty")

    let requested = splitFile(requestedName).name
    var faceIndex = requestedFaceIndex
    if faceIndex >= 0 and faceIndex notin 0 ..< typefaces.len:
      raise
        newException(PixieError, "requested typeface collection face is not available")
    if faceIndex < 0:
      faceIndex = 0
      var matchScore = high(int)
      for index, typeface in typefaces:
        let score = fontNameMatchScore(requested, typeface.name())
        if score >= 0 and score < matchScore:
          faceIndex = index
          matchScore = score

    result.typeface = typefaces[faceIndex]
    result.typeface.filePath = path & "#" & $faceIndex
    try:
      result.source = TypefaceSource(
        name: path,
        data: readFile(path),
        kind: typefaceKindFromPath(path),
        faceIndex: faceIndex,
      )
    except IOError as e:
      raise newException(PixieError, e.msg, e)
  else:
    if requestedFaceIndex > 0:
      raise newException(PixieError, "standalone typeface face index must be zero")
    try:
      let data = readFile(path)
      let kind = typefaceKindFromPath(path)
      result.typeface = readTypefaceImpl(path, data, kind)
      result.source = TypefaceSource(name: path, data: data, kind: kind)
    except IOError as e:
      raise newException(PixieError, e.msg, e)

proc sameTypefaceSource(a, b: TypefaceSource): bool {.inline.} =
  a.kind == b.kind and a.faceIndex == b.faceIndex and a.data == b.data

proc typefaceIdForLocked(source: TypefaceSource): TypefaceId =
  let sourceHash = hash((source.kind, source.faceIndex, source.data))
  for salt in 0 .. 100:
    let candidateHash =
      if salt == 0:
        sourceHash
      else:
        hash((sourceHash, salt))
    if candidateHash != Hash(0):
      let candidate = TypefaceId(candidateHash)
      if candidate notin typefaceSourceTable or
          typefaceSourceTable[candidate].sameTypefaceSource(source):
        return candidate

  raise newException(ValueError, "could not allocate a collision-free typeface id")

proc registerTypeface(typeface: Typeface, source: sink TypefaceSource): TypefaceId =
  var info = parseTypefaceInfo(
    source.name, source.data, source.faceIndex, fallbackFullName = typeface.name()
  )
  withLock(fontLock):
    result = typefaceIdForLocked(source)
    if result notin typefaceSourceTable:
      typefaceSourceTable[result] = ensureMove source
      typefaceInfoTable[result] = ensureMove info
  if result notin typefaceTable:
    typefaceTable[result] = typeface

proc staticTypefaceEntry(
    name: string, entry: var tuple[name: string, data: string, kind: TypeFaceKinds]
): bool =
  withLock(fontLock):
    for key in lookupTypefaceNames(name):
      if key in staticTypefaceTable:
        entry = staticTypefaceTable[key]
        return true

proc hasStaticTypeface*(name: string): bool =
  ## Whether a name or filename alias has a static typeface registration.
  var entry: tuple[name: string, data: string, kind: TypeFaceKinds]
  staticTypefaceEntry(name, entry)

proc canLoadTypeface*(path, requiredText: string): bool =
  ## Checks whether Pixie can read a file and map all runes in requiredText.
  ## Does not register the face. Unreadable or unsupported files return false.
  try:
    let typeface = readTypeface(path)
    for rune in requiredText.runes:
      if not typeface.hasGlyph(rune):
        return false
    result = true
  except CatchableError:
    result = false

proc canLoadTypeface*(path: string): bool =
  ## Checks whether Pixie can read a file without registering the face.
  canLoadTypeface(path, "")

proc loadTypeface*(name: string, fallbackNames: openArray[string]): TypefaceId =
  ## loads a font from a file and adds it to the font index

  proc resolveTypefacePath(name: string): ResolvedTypefacePath =
    let dataPath = figDataDir() / name
    if fileExists(dataPath):
      info "resolved typeface from figDataDir", requested = name, path = dataPath
      return ResolvedTypefacePath(path: dataPath, faceIndex: -1)

    if fileExists(name):
      info "resolved typeface from direct path", requested = name, path = name
      return ResolvedTypefacePath(path: name, faceIndex: -1)

    if splitFile(name).ext.len > 0:
      let filePath = findSystemFontFile([name])
      if filePath.len > 0:
        info "resolved typeface from exact system font filename",
          requested = name, path = filePath
        return ResolvedTypefacePath(path: filePath, faceIndex: -1)

    let systemTypeface = findSystemTypeface([name])
    if systemTypeface.isSome:
      let matchedTypeface = systemTypeface.get()
      info "resolved typeface from system font service",
        requested = name,
        path = matchedTypeface.file.path,
        faceIndex = matchedTypeface.file.faceIndex
      return ResolvedTypefacePath(
        path: matchedTypeface.file.path, faceIndex: matchedTypeface.file.faceIndex
      )

    let alias = splitFile(name).name.toLowerAscii().replace("-", "")
    if alias in ["sfns", "ubuntur"]:
      let filePath = findSystemFontFile([name])
      if filePath.len > 0:
        info "resolved typeface from system font alias",
          requested = name, path = filePath
        return ResolvedTypefacePath(path: filePath, faceIndex: -1)

    warn "unable to resolve typeface path", requested = name, figDataDir = figDataDir()
    result.faceIndex = -1

  var candidateNames = @[name]
  candidateNames.add(fallbackNames)
  candidateNames.add(systemDefaultFontNames())

  var loaded = false
  var typeface: Typeface
  var source: TypefaceSource
  for candidate in candidateNames:
    let resolved = resolveTypefacePath(candidate)
    if resolved.path.len > 0:
      try:
        (typeface, source) =
          readTypefacePath(resolved.path, candidate, resolved.faceIndex)
        loaded = true
        break
      except PixieError:
        warn "failed to read resolved typeface path",
          requested = name, candidate = candidate, path = resolved.path

    var staticEntry: tuple[name: string, data: string, kind: TypeFaceKinds]
    if candidate.staticTypefaceEntry(staticEntry):
      try:
        info "resolved typeface from static registry",
          requested = name, candidate = candidate, staticName = staticEntry.name
        typeface =
          readTypefaceImpl(staticEntry.name, staticEntry.data, staticEntry.kind)
        source = TypefaceSource(
          name: staticEntry.name, data: staticEntry.data, kind: staticEntry.kind
        )
        loaded = true
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

  result = registerTypeface(typeface, source)

proc loadTypeface*(name: string): TypefaceId =
  loadTypeface(name, [])

proc loadTypeface*(file: SystemTypefaceFile): TypefaceId =
  ## Loads the physical face in `file`.
  if file.path.len == 0:
    raise newException(PixieError, "typeface path is empty")
  if file.faceIndex < 0:
    raise newException(PixieError, "typeface face index must not be negative")
  let (typeface, source) = readTypefacePath(file.path, file.path, file.faceIndex)
  result = registerTypeface(typeface, source)
  info "loaded typeface from exact file", path = file.path, faceIndex = file.faceIndex

proc fontWithSize*(typeface: SystemTypeface, size: float32): FigFont =
  ## Loads an exact installed typeface and applies its variable-axis coordinates.
  result = loadTypeface(typeface.file).fontWithSize(size)
  result.variations = typeface.variations

proc loadTypeface*(name, data: string, kind: TypeFaceKinds): TypefaceId =
  ## loads a font from buffer and adds it to the font index

  let typeface = readTypefaceImpl(name, data, kind)
  result =
    registerTypeface(typeface, TypefaceSource(name: name, data: data, kind: kind))

proc tryGetTypefaceSource*(id: TypefaceId, value: var TypefaceSource): bool =
  ## Copies a registered source; returns false without changing value if absent.
  {.cast(gcsafe).}:
    withLock(fontLock):
      if id notin typefaceSourceTable:
        return false
      value = typefaceSourceTable[id]
      result = true

proc getTypefaceSource*(id: TypefaceId): TypefaceSource =
  if not tryGetTypefaceSource(id, result):
    raise newException(
      ValueError, "typeface source data is not available for id " & $Hash(id)
    )

proc getTypefaceInfo*(id: TypefaceId): TypefaceInfo =
  ## Returns backend-neutral metadata cached when the typeface was registered.
  ##
  ## This API is identical for the Pixie, Harfbuzzy, and hybrid text backends.
  {.cast(gcsafe).}:
    withLock(fontLock):
      if id notin typefaceInfoTable:
        raise newException(
          ValueError, "typeface metadata is not available for id " & $Hash(id)
        )
      result = typefaceInfoTable[id].copyTypefaceInfo()

proc tryGetTypefaceInfo*(id: TypefaceId, value: var TypefaceInfo): bool =
  ## Copies registered metadata; returns false without changing value if absent.
  {.cast(gcsafe).}:
    withLock(fontLock):
      if id notin typefaceInfoTable:
        return false
      value = typefaceInfoTable[id].copyTypefaceInfo()
      result = true

proc tryGetFigFont*(fontId: FontId, value: var FigFont): bool =
  ## Copies a registered font; returns false without changing value if absent.
  {.cast(gcsafe).}:
    withLock(fontLock):
      if fontId notin fontTable:
        return false
      value = fontTable[fontId]
      result = true

proc getFigFont*(fontId: FontId): FigFont =
  if not tryGetFigFont(fontId, result):
    raise newException(ValueError, "font is not available for id " & $Hash(fontId))

proc readTypefaceForThread(source: TypefaceSource): Typeface =
  if source.data.len >= 4 and source.data[0 ..< 4] == "ttcf":
    let typefaces = readTypefaces(source.name)
    if source.faceIndex notin 0 ..< typefaces.len:
      raise newException(PixieError, "typeface collection face is not available")
    result = typefaces[source.faceIndex]
    result.filePath = source.name & "#" & $source.faceIndex
  else:
    result = readTypefaceImpl(source.name, source.data, source.kind)

proc pixieTypeface(typefaceId: TypefaceId): Typeface =
  if typefaceId notin typefaceTable:
    typefaceTable[typefaceId] = readTypefaceForThread(getTypefaceSource(typefaceId))
  result = typefaceTable[typefaceId]

proc pixieFont(font: FigFont): Font =
  let typeface = font.typefaceId.pixieTypeface()

  result = newFont(typeface)
  result.size = font.size
  result.typeface = typeface
  result.textCase = parseEnum[TextCase]($font.fontCase)
  result.lineHeight = font.lineHeight
  result.underline = font.underline
  result.strikethrough = font.strikethrough
  result.noKerningAdjustments = font.noKerningAdjustments

  if font.lineHeight == 0.0'f32:
    result.lineHeight = result.defaultLineHeight()

proc rasterFont(font: FigFont): FigFont =
  FigFont(
    typefaceId: font.typefaceId,
    size: font.size,
    fontCase: font.fontCase,
    variations: font.variations,
  )

proc registerFont(font: FigFont): FontId =
  var raster = font.rasterFont()
  let
    uiScale = figUiScale()
    fontHash = hash((raster.getId(), uiScale))

  {.cast(gcsafe).}:
    withLock(fontLock):
      for salt in 0 .. 100:
        let candidateHash =
          if salt == 0:
            fontHash
          else:
            hash((fontHash, salt))
        if candidateHash != Hash(0):
          let candidate = FontId(candidateHash)
          if candidate notin fontTable:
            fontTable[candidate] = ensureMove raster
            fontUiScaleTable[candidate] = uiScale
            return candidate
          if fontTable[candidate] == raster and
              fontUiScaleTable.getOrDefault(candidate, uiScale) == uiScale:
            return candidate

  raise newException(ValueError, "could not allocate a collision-free font id")

proc convertFont*(font: FigFont): (FontId, Font) =
  ## does the typesetting using pixie, then converts to Figuro's internal
  ## types

  result = (font.registerFont(), font.pixieFont())

proc convertFont*(style: FontStyle): (FontId, Font) =
  style.font.convertFont()

proc cacheFont*(font: FigFont): FontId =
  ## Registers the font's raster settings and returns its cache identity.
  font.convertFont()[0]

proc defaultFontLineHeight*(font: FigFont): float32 =
  ## Returns the default line height for the font at its unscaled size.
  font.pixieFont().defaultLineHeight()

proc fontRef*(font: sink FigFont): FontRef =
  ## Retain a font cache ID for the current thread.
  let (fontId, _) = font.convertFont()
  retainFontRefId(fontId)
  new result
  result.value = ensureMove font
  result.id = fontId

proc fontRef*(typefaceId: TypefaceId, size: float32): FontRef =
  ## Build a FigFont from a typeface and size, then retain its font cache ID.
  fontRef(fontWithSize(typefaceId, size))

proc clearFontGlyphs*(font: FigFont) =
  clearFontGlyphs(font.convertFont()[0])

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
    glyph: GlyphFont(
      fontId: fontId,
      size: uiFont.size,
      lineHeight: lineHeight,
      descentAdj: baselineOffset,
      underline: uiFont.underline,
      strikethrough: uiFont.strikethrough,
    ),
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
  let uifont = getFigFont(fontId)
  result = uifont.pixieFont()
  result.size = result.size.getScaledFont()
  #result.size = result.size
  result.lineHeight = result.lineHeight.scaled()
