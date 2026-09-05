import std/options

type
  SystemTypefaceFile* = object
    ## An installed font file and the selected face within it.
    path*: string
    faceIndex*: int ## Zero-based face index, including for standalone fonts.

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
