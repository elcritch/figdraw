import std/[algorithm, hashes, math, options]

from ../common/fonttypes import FontVariation

type
  SystemTypefaceFile* = object
    ## A locally readable font file and the selected physical face within it.
    path*: string
    faceIndex*: int ## Zero-based face index, including for standalone fonts.

  SystemTypeface* = object
    ## An exact installed typeface selection.
    ##
    ## `file` identifies the physical OpenType face. `variations` distinguishes
    ## named instances that share a variable-font face.
    file*: SystemTypefaceFile
    variations*: seq[FontVariation]

  SystemTypefaceInfo* = object
    ## Names and exact identity reported by a platform font provider.
    ##
    ## Names are provider-selected display metadata and may differ from the
    ## OpenType names parsed from `typeface`. Empty names are permitted.
    typeface*: SystemTypeface
    family*: string
    subfamily*: string
    fullName*: string
    postScriptName*: string

  SystemTypefaceQuery* = object
    ## Exact filters for installed typeface enumeration.
    ##
    ## Empty fields are wildcards. Populated fields are combined with AND.
    family*: string
    subfamily*: string

  SystemFontProviderResult* = object
    ## Result from a platform font provider.
    ##
    ## `available` distinguishes an unavailable provider from a valid lookup
    ## that found no matching installed face.
    available*: bool
    match*: Option[SystemTypeface]

func initSystemTypefaceFile*(path: string, faceIndex: Natural = 0): SystemTypefaceFile =
  ## Creates a physical system-typeface file identity.
  SystemTypefaceFile(path: path, faceIndex: faceIndex)

func canonicalVariations(
    variations: openArray[FontVariation] = []
): seq[FontVariation] =
  result = @variations
  result.sort(
    proc(left, right: FontVariation): int =
      cmp(left.tag, right.tag)
  )
  for index, variation in result:
    if variation.tag.len != 4:
      raise newException(ValueError, "font variation tags must contain four bytes")
    for ch in variation.tag:
      if ch notin {'\x20' .. '\x7e'}:
        raise newException(ValueError, "font variation tags must be printable ASCII")
    if variation.value.classify in {fcNan, fcInf, fcNegInf}:
      raise newException(ValueError, "font variation values must be finite")
    if index > 0 and variation.tag == result[index - 1].tag:
      raise newException(ValueError, "font variation tags must be unique")

func initSystemTypeface*(
    file: SystemTypefaceFile, variations: openArray[FontVariation] = []
): SystemTypeface =
  ## Creates an exact system-typeface identity with canonical axis ordering.
  if file.faceIndex < 0:
    raise newException(ValueError, "system typeface face index must not be negative")
  SystemTypeface(file: file, variations: canonicalVariations(variations))

func initSystemTypeface*(
    path: string, faceIndex: Natural = 0, variations: openArray[FontVariation] = []
): SystemTypeface =
  ## Creates an exact system-typeface identity from a path and physical face index.
  initSystemTypeface(initSystemTypefaceFile(path, faceIndex), variations)

proc hash*(file: SystemTypefaceFile): Hash =
  hash((file.path, file.faceIndex))

proc hash*(typeface: SystemTypeface): Hash =
  hash((typeface.file, typeface.variations))

func unavailableSystemFontProvider*(): SystemFontProviderResult {.inline.} =
  SystemFontProviderResult()

func systemFontProviderMatch*(
    match: Option[SystemTypeface]
): SystemFontProviderResult {.inline.} =
  SystemFontProviderResult(available: true, match: match)
