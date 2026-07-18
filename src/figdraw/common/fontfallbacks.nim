import ./fonttypes

type
  FontFallbackRequest* = object
    ## Describes source codepoints that the currently available typefaces do not
    ## cover. Resolvers may return one or more additional typefaces to retry.
    primaryTypefaceId*: TypefaceId
    existingTypefaceIds*: seq[TypefaceId]
    language*: string
    script*: string
    codepoints*: seq[uint32]

  FontFallbackResolver* =
    proc(request: FontFallbackRequest): seq[TypefaceId] {.closure.}
    ## Resolves additional typefaces on demand for a missing-coverage request.

var activeFontFallbackResolver {.threadvar.}: FontFallbackResolver

proc fontFallbackResolver*(): FontFallbackResolver =
  ## Returns the fallback resolver installed on the current thread.
  activeFontFallbackResolver

proc `fontFallbackResolver=`*(resolver: FontFallbackResolver) =
  ## Installs a fallback resolver on the current thread.
  activeFontFallbackResolver = resolver
