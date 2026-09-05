## Native installed-font matching through Fontconfig on Linux and FreeBSD.
##
## The ABI is loaded at runtime so systems without Fontconfig can fall back to
## directory scanning without failing to start or link.

import std/[dynlib, locks, options, os, unicode]

import ./systemfonttypes

type
  FcBool = cint
  FcChar8 = uint8
  FcResult = cint
  FcMatchKind = cint
  FcPattern {.incompleteStruct.} = object
  FcConfig {.incompleteStruct.} = object

  FcInitLoadConfigAndFontsProc = proc(): ptr FcConfig {.cdecl.}
  FcConfigDestroyProc = proc(config: ptr FcConfig) {.cdecl.}
  FcPatternCreateProc = proc(): ptr FcPattern {.cdecl.}
  FcPatternDestroyProc = proc(pattern: ptr FcPattern) {.cdecl.}
  FcPatternAddStringProc = proc(
    pattern: ptr FcPattern, objectName: cstring, value: ptr FcChar8
  ): FcBool {.cdecl.}
  FcPatternAddIntegerProc =
    proc(pattern: ptr FcPattern, objectName: cstring, value: cint): FcBool {.cdecl.}
  FcConfigSubstituteProc = proc(
    config: ptr FcConfig, pattern: ptr FcPattern, kind: FcMatchKind
  ): FcBool {.cdecl.}
  FcDefaultSubstituteProc = proc(pattern: ptr FcPattern) {.cdecl.}
  FcFontMatchProc = proc(
    config: ptr FcConfig, pattern: ptr FcPattern, matchResult: ptr FcResult
  ): ptr FcPattern {.cdecl.}
  FcPatternGetStringProc = proc(
    pattern: ptr FcPattern, objectName: cstring, index: cint, value: ptr ptr FcChar8
  ): FcResult {.cdecl.}
  FcPatternGetIntegerProc = proc(
    pattern: ptr FcPattern, objectName: cstring, index: cint, value: ptr cint
  ): FcResult {.cdecl.}

  FontconfigApi = object
    library: LibHandle
    initLoadConfigAndFonts: FcInitLoadConfigAndFontsProc
    configDestroy: FcConfigDestroyProc
    patternCreate: FcPatternCreateProc
    patternDestroy: FcPatternDestroyProc
    patternAddString: FcPatternAddStringProc
    patternAddInteger: FcPatternAddIntegerProc
    configSubstitute: FcConfigSubstituteProc
    defaultSubstitute: FcDefaultSubstituteProc
    fontMatch: FcFontMatchProc
    patternGetString: FcPatternGetStringProc
    patternGetInteger: FcPatternGetIntegerProc

const
  fcResultMatch = FcResult(0)
  fcMatchPattern = FcMatchKind(0)
  fcWeightRegular = cint(80)
  fcSlantRoman = cint(0)
  fcFamily: cstring = "family"
  fcFullName: cstring = "fullname"
  fcPostscriptName: cstring = "postscriptname"
  fcStyle: cstring = "style"
  fcFile: cstring = "file"
  fcIndex: cstring = "index"
  fcWeight: cstring = "weight"
  fcSlant: cstring = "slant"

var
  apiLock: Lock
  apiLoadAttempted: bool
  apiLoaded: bool
  api: FontconfigApi

apiLock.initLock()

proc loadSymbol[T](library: LibHandle, name: cstring): T {.inline.} =
  cast[T](library.symAddr(name))

proc loadFontconfigApi(): bool =
  withLock(apiLock):
    if apiLoadAttempted:
      return apiLoaded
    apiLoadAttempted = true

    const libraryNames = ["libfontconfig.so.1", "libfontconfig.so"]
    for name in libraryNames:
      api.library = loadLib(name)
      if api.library != nil:
        break
    if api.library == nil:
      return false

    api.initLoadConfigAndFonts =
      loadSymbol[FcInitLoadConfigAndFontsProc](api.library, "FcInitLoadConfigAndFonts")
    api.configDestroy = loadSymbol[FcConfigDestroyProc](api.library, "FcConfigDestroy")
    api.patternCreate = loadSymbol[FcPatternCreateProc](api.library, "FcPatternCreate")
    api.patternDestroy =
      loadSymbol[FcPatternDestroyProc](api.library, "FcPatternDestroy")
    api.patternAddString =
      loadSymbol[FcPatternAddStringProc](api.library, "FcPatternAddString")
    api.patternAddInteger =
      loadSymbol[FcPatternAddIntegerProc](api.library, "FcPatternAddInteger")
    api.configSubstitute =
      loadSymbol[FcConfigSubstituteProc](api.library, "FcConfigSubstitute")
    api.defaultSubstitute =
      loadSymbol[FcDefaultSubstituteProc](api.library, "FcDefaultSubstitute")
    api.fontMatch = loadSymbol[FcFontMatchProc](api.library, "FcFontMatch")
    api.patternGetString =
      loadSymbol[FcPatternGetStringProc](api.library, "FcPatternGetString")
    api.patternGetInteger =
      loadSymbol[FcPatternGetIntegerProc](api.library, "FcPatternGetInteger")

    apiLoaded =
      api.initLoadConfigAndFonts != nil and api.configDestroy != nil and
      api.patternCreate != nil and api.patternDestroy != nil and
      api.patternAddString != nil and api.patternAddInteger != nil and
      api.configSubstitute != nil and api.defaultSubstitute != nil and
      api.fontMatch != nil and api.patternGetString != nil and
      api.patternGetInteger != nil
    if not apiLoaded:
      unloadLib(api.library)
      api.library = nil
    result = apiLoaded

proc normalizeFontName(name: string): string =
  result = newStringOfCap(name.len)
  for rune in name.runes:
    if $rune notin [" ", "-", "_", "."]:
      result.add($rune.toLower)

proc patternStrings(pattern: ptr FcPattern, objectName: cstring): seq[string] =
  var index = cint(0)
  while true:
    var value: ptr FcChar8
    if api.patternGetString(pattern, objectName, index, addr value) != fcResultMatch:
      break
    if value != nil:
      result.add($cast[cstring](value))
    inc index

proc patternInteger(
    pattern: ptr FcPattern, objectName: cstring, value: var cint
): bool =
  api.patternGetInteger(pattern, objectName, 0, addr value) == fcResultMatch

proc isRegularFace(pattern: ptr FcPattern): bool =
  let styles = pattern.patternStrings(fcStyle)
  for style in styles:
    if style.normalizeFontName() in ["regular", "normal", "book", "roman", "plain"]:
      var slant: cint
      return not pattern.patternInteger(fcSlant, slant) or slant == fcSlantRoman

  var weight, slant: cint
  pattern.patternInteger(fcWeight, weight) and weight == fcWeightRegular and
    (not pattern.patternInteger(fcSlant, slant) or slant == fcSlantRoman)

proc matchesRequestedName(pattern: ptr FcPattern, requestedName: string): bool =
  let
    requested = requestedName.normalizeFontName()
    families = pattern.patternStrings(fcFamily)
    fullNames = pattern.patternStrings(fcFullName)
    postscriptNames = pattern.patternStrings(fcPostscriptName)
    styles = pattern.patternStrings(fcStyle)

  if requested.len == 0:
    return false
  for fullName in fullNames:
    if fullName.normalizeFontName() == requested:
      return true
  for postscriptName in postscriptNames:
    if postscriptName.normalizeFontName() == requested:
      return true
  for family in families:
    let normalizedFamily = family.normalizeFontName()
    for style in styles:
      if normalizedFamily & style.normalizeFontName() == requested:
        return true
    if normalizedFamily == requested and pattern.isRegularFace():
      return true

proc queryFontconfig(
    config: ptr FcConfig,
    requestedName: string,
    queryObject: cstring,
    regularFamily: bool,
): Option[SystemTypefaceFile] =
  let query = api.patternCreate()
  if query == nil:
    return
  defer:
    api.patternDestroy(query)

  if api.patternAddString(query, queryObject, cast[ptr FcChar8](requestedName.cstring)) ==
      0:
    return
  if regularFamily:
    if api.patternAddInteger(query, fcWeight, fcWeightRegular) == 0 or
        api.patternAddInteger(query, fcSlant, fcSlantRoman) == 0:
      return
  if api.configSubstitute(config, query, fcMatchPattern) == 0:
    return
  api.defaultSubstitute(query)

  var matchResult: FcResult
  let matched = api.fontMatch(config, query, addr matchResult)
  if matched == nil:
    return
  defer:
    api.patternDestroy(matched)
  if matchResult != fcResultMatch or not matched.matchesRequestedName(requestedName):
    return

  var
    fileValue: ptr FcChar8
    faceIndex: cint
  if api.patternGetString(matched, fcFile, 0, addr fileValue) != fcResultMatch or
      fileValue == nil or
      api.patternGetInteger(matched, fcIndex, 0, addr faceIndex) != fcResultMatch or
      faceIndex < 0:
    return
  let
    path = $cast[cstring](fileValue)
    packedIndex = cast[uint32](faceIndex)
  # Fontconfig packs a variable-font named-instance number above the low
  # 16-bit collection index. FigDraw cannot represent those coordinates in a
  # SystemTypefaceFile, so accepting one would load a different design.
  if packedIndex > 0xFFFF'u32 or not path.isAbsolute() or not path.fileExists():
    return
  some(SystemTypefaceFile(path: path, faceIndex: int(packedIndex)))

proc findNativeSystemTypefaceFile*(names: openArray[string]): SystemFontProviderResult =
  ## Finds the first exact installed face requested through Fontconfig.
  ##
  ## Fontconfig deliberately returns a closest match. This provider validates
  ## that match's family, full name, or PostScript name before accepting it.
  if not loadFontconfigApi():
    return unavailableSystemFontProvider()

  let config = api.initLoadConfigAndFonts()
  if config == nil:
    return unavailableSystemFontProvider()
  defer:
    api.configDestroy(config)

  for name in names:
    if name.len == 0:
      continue
    for queryObject in [fcFullName, fcPostscriptName]:
      let matched = queryFontconfig(config, name, queryObject, false)
      if matched.isSome:
        return systemFontProviderMatch(matched)
    let matched = queryFontconfig(config, name, fcFamily, true)
    if matched.isSome:
      return systemFontProviderMatch(matched)
  systemFontProviderMatch(none(SystemTypefaceFile))
