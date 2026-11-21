## FigDraw's shared registry of caller-supplied hyphenation patterns.

import std/[isolation, locks, os, strutils, tables]
import threading/smartptrs
import pkg/harfbuzzy/hyphenation as patternsModule

export patternsModule

var
  registryLock: Lock
  registry: Table[string, ConstPtr[HyphenationPatterns]]

initLock(registryLock)

func normalizedLanguage(language: string): string =
  language.toLowerAscii().replace('_', '-')

proc registerHyphenationPatterns*(
    language: string, patterns: sink HyphenationPatterns
) =
  ## Makes `patterns` available to every thread for a BCP 47 language such as
  ## `en-US` or `en`. The empty language is the fallback for unmatched text.
  let shared = newConstPtr(unsafeIsolate(move patterns))
  {.cast(gcsafe).}:
    withLock(registryLock):
      registry[language.normalizedLanguage()] = shared

proc unregisterHyphenationPatterns*(language: string) =
  {.cast(gcsafe).}:
    withLock(registryLock):
      registry.del(language.normalizedLanguage())

proc clearHyphenationPatterns*() =
  {.cast(gcsafe).}:
    withLock(registryLock):
      registry.clear()

proc hyphenationPatternsFor*(
    language: string, patterns: var ConstPtr[HyphenationPatterns]
): bool =
  ## Finds patterns for `language`, then its primary subtag, then the first
  ## regional variant of that subtag in sorted order, then the empty fallback.
  let
    normalized = language.normalizedLanguage()
    dash = normalized.find('-')
    primary =
      if dash > 0:
        normalized[0 ..< dash]
      else:
        normalized
  {.cast(gcsafe).}:
    withLock(registryLock):
      for candidate in [normalized, primary]:
        if candidate in registry:
          patterns = registry[candidate]
          return true
      if primary.len > 0:
        var variant = ""
        for key in registry.keys:
          if key.startsWith(primary & "-") and (variant.len == 0 or key < variant):
            variant = key
        if variant.len > 0:
          patterns = registry[variant]
          return true
      if "" in registry:
        patterns = registry[""]
        return true

proc hasHyphenationPatterns*(language: string): bool =
  var patterns: ConstPtr[HyphenationPatterns]
  hyphenationPatternsFor(language, patterns)

proc registerHyphenationDirectory*(directory: string): seq[string] =
  ## Registers every recognized pattern file in `directory`, like an asset
  ## folder of hyph-utf8 or LibreOffice dictionaries, and returns the
  ## languages added. Unreadable or malformed files are skipped.
  for kind, path in walkDir(directory):
    if kind notin {pcFile, pcLinkToFile}:
      continue
    let language = path.patternFileLanguage()
    if language.len == 0:
      continue
    try:
      registerHyphenationPatterns(language, loadHyphenationPatterns(path))
      result.add language
    except CatchableError:
      discard

proc hyphenationPoints*(language, word: string): seq[int] =
  ## Hyphenation points for `word` using registered patterns, if any.
  var patterns: ConstPtr[HyphenationPatterns]
  if hyphenationPatternsFor(language, patterns):
    result = patterns[].hyphenationPoints(word)
