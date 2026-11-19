## Liang hyphenation patterns and a per-language registry used by paragraph
## layout. FigDraw ships no language data; applications register patterns,
## for example TeX `hyph-*.tex` files or LibreOffice `hyph_*.dic` dictionaries.

import std/[isolation, locks, os, strutils, tables, unicode]
import threading/smartptrs

type HyphenationPatterns* = object
  ## Compiled Liang patterns and exceptions for one language.
  patterns: Table[string, seq[uint8]]
  exceptions: Table[string, seq[int]]
  maxPatternRunes: int
  leftMin*: int ## Minimum runes before the first hyphen.
  rightMin*: int ## Minimum runes after the last hyphen.

proc initHyphenationPatterns*(leftMin = 2, rightMin = 3): HyphenationPatterns =
  HyphenationPatterns(leftMin: max(leftMin, 1), rightMin: max(rightMin, 1))

func len*(patterns: HyphenationPatterns): int =
  ## Number of compiled patterns, excluding exceptions.
  patterns.patterns.len

proc addPattern*(patterns: var HyphenationPatterns, token: string) =
  ## Adds one Liang pattern such as `hy3ph` or `.ex5am`.
  var
    letters = newStringOfCap(token.len)
    values = @[0'u8]
  for rune in token.runes:
    if rune.int in '0'.ord .. '9'.ord:
      values[^1] = uint8(rune.int - '0'.ord)
    else:
      letters.add rune.toLower
      values.add 0
  if values.len < 2:
    return
  patterns.maxPatternRunes = max(patterns.maxPatternRunes, values.len - 1)
  patterns.patterns[letters] = values

proc addException*(patterns: var HyphenationPatterns, word: string) =
  ## Adds a fixed hyphenation such as `ta-ble`, overriding the patterns.
  var
    letters = newStringOfCap(word.len)
    points: seq[int]
    count = 0
  for rune in word.runes:
    if rune == Rune('-'):
      if count > 0:
        points.add count
    else:
      letters.add rune.toLower
      inc count
  if count > 0:
    patterns.exceptions[letters] = points

proc stripComment(line: string): string =
  let comment = line.find('%')
  if comment >= 0:
    line[0 ..< comment]
  else:
    line

proc parseTexHyphenationPatterns*(
    text: string, leftMin = 2, rightMin = 3
): HyphenationPatterns =
  ## Parses TeX `\patterns{...}` and `\hyphenation{...}` groups. Text without
  ## TeX groups is read as whitespace-separated patterns.
  result = initHyphenationPatterns(leftMin, rightMin)
  var cleaned = newStringOfCap(text.len)
  for line in text.splitLines():
    cleaned.add line.stripComment()
    cleaned.add '\n'
  if "\\patterns" notin cleaned and "\\hyphenation" notin cleaned:
    for token in strutils.splitWhitespace(cleaned):
      result.addPattern(token)
    return
  var position = 0
  while position < cleaned.len:
    let command = cleaned.find('\\', position)
    if command < 0:
      break
    let
      open = cleaned.find('{', command)
      close =
        if open >= 0:
          cleaned.find('}', open)
        else:
          -1
    if open < 0 or close < 0:
      break
    let
      name = cleaned[command + 1 ..< open].strip()
      body = cleaned[open + 1 ..< close]
    if name == "patterns":
      for token in strutils.splitWhitespace(body):
        result.addPattern(token)
    elif name == "hyphenation":
      for token in strutils.splitWhitespace(body):
        result.addException(token)
    position = close + 1

proc latin1ToUtf8(text: string): string =
  result = newStringOfCap(text.len)
  for ch in text:
    result.add Rune(ch.ord)

proc parseHyphenDictionary*(text: string): HyphenationPatterns =
  ## Parses a LibreOffice/Hunspell hyphen `.dic` dictionary. The first line
  ## names its encoding; UTF-8 and ISO8859-1 are supported. Nonstandard
  ## patterns and second-level compound patterns are skipped.
  ## Raises `ValueError` for other encodings.
  result = initHyphenationPatterns()
  let
    firstBreak = text.find('\n')
    header = (if firstBreak < 0: text else: text[0 ..< firstBreak]).strip()
    encoding = header.toLowerAscii()
    body =
      if firstBreak < 0:
        ""
      else:
        text[firstBreak + 1 .. ^1]
    utf8 =
      if encoding in ["utf-8", "utf8"]:
        body
      elif encoding in ["iso8859-1", "iso-8859-1", "latin1"]:
        body.latin1ToUtf8()
      else:
        raise
          newException(ValueError, "unsupported hyphen dictionary encoding: " & header)
  for rawLine in utf8.splitLines():
    let line = rawLine.stripComment().strip()
    if line.len == 0:
      continue
    let fields = strutils.splitWhitespace(line)
    case fields[0]
    of "LEFTHYPHENMIN":
      if fields.len > 1:
        result.leftMin = max(parseInt(fields[1]), 1)
    of "RIGHTHYPHENMIN":
      if fields.len > 1:
        result.rightMin = max(parseInt(fields[1]), 1)
    of "NEXTLEVEL":
      break
    of "COMPOUNDLEFTHYPHENMIN", "COMPOUNDRIGHTHYPHENMIN", "NOHYPHEN":
      discard
    else:
      if '/' notin line:
        result.addPattern(fields[0])

proc addExceptions*(patterns: var HyphenationPatterns, text: string) =
  ## Adds whitespace-separated exceptions such as hyph-utf8 `.hyp.txt` files.
  for line in text.splitLines():
    for token in strutils.splitWhitespace(line.stripComment()):
      patterns.addException(token)

proc loadHyphenationPatterns*(path: string): HyphenationPatterns =
  ## Loads a LibreOffice `.dic` dictionary, a TeX pattern file, or a hyph-utf8
  ## `.pat.txt` file. A sibling `.hyp.txt` file supplies exceptions.
  let text = readFile(path)
  if path.toLowerAscii().endsWith(".dic"):
    return parseHyphenDictionary(text)
  result = parseTexHyphenationPatterns(text)
  if path.endsWith(".pat.txt"):
    let exceptions = path[0 ..< path.len - ".pat.txt".len] & ".hyp.txt"
    if fileExists(exceptions):
      result.addExceptions(readFile(exceptions))

func patternFileLanguage*(path: string): string =
  ## Language named by a pattern file: `hyph-en-us.pat.txt`, `hyph-de.tex`,
  ## or `hyph_en_US.dic`. Returns "" for other names.
  var name = path.extractFilename()
  let lower = name.toLowerAscii()
  for suffix in [".pat.txt", ".tex", ".dic"]:
    if lower.endsWith(suffix):
      name = name[0 ..< name.len - suffix.len]
      if name.len > 5 and name[0 .. 3].toLowerAscii() == "hyph" and name[4] in {
        '-', '_'
      }:
        return name[5 .. ^1].toLowerAscii().replace('_', '-')
      return ""

proc hyphenationPoints*(patterns: HyphenationPatterns, word: string): seq[int] =
  ## Returns ascending rune counts after which `word` may be hyphenated.
  ## Words containing non-letters are not hyphenated.
  var runes = newSeqOfCap[Rune](word.len + 2)
  runes.add Rune('.')
  for rune in word.runes:
    if not rune.isAlpha:
      return
    runes.add rune.toLower
  runes.add Rune('.')
  let letters = runes.len - 2
  if letters < patterns.leftMin + patterns.rightMin:
    return
  if patterns.exceptions.len > 0:
    var key = newStringOfCap(word.len)
    for index in 1 .. letters:
      key.add runes[index]
    if key in patterns.exceptions:
      for point in patterns.exceptions[key]:
        if point >= patterns.leftMin and point <= letters - patterns.rightMin:
          result.add point
      return
  var values = newSeq[uint8](runes.len + 1)
  var key = newStringOfCap(patterns.maxPatternRunes * 4)
  for start in 0 ..< runes.len:
    key.setLen(0)
    for stop in start ..< min(runes.len, start + patterns.maxPatternRunes):
      key.add runes[stop]
      if key in patterns.patterns:
        for offset, value in patterns.patterns[key]:
          if value > values[start + offset]:
            values[start + offset] = value
  for point in patterns.leftMin .. letters - patterns.rightMin:
    if values[point + 1] mod 2 == 1:
      result.add point

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
