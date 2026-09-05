import std/options

type
  SystemTypefaceFile* = object
    ## An installed font file and the selected face within it.
    path*: string
    faceIndex*: int ## Zero-based face index, including for standalone fonts.

  SystemTypefaceInfo* = object
    ## Names and local file identity reported by a platform font provider.
    ##
    ## Names are provider-selected display metadata and may differ from the
    ## OpenType names parsed from `file`. Empty names are permitted.
    file*: SystemTypefaceFile
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
    match*: Option[SystemTypefaceFile]

func unavailableSystemFontProvider*(): SystemFontProviderResult {.inline.} =
  SystemFontProviderResult()

func systemFontProviderMatch*(
    match: Option[SystemTypefaceFile]
): SystemFontProviderResult {.inline.} =
  SystemFontProviderResult(available: true, match: match)
