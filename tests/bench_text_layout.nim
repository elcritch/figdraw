## Measures paragraph layout throughput for each available text backend.
##
##   nim r -d:release tests/bench_text_layout.nim
##
## Pass `--mixed` for accented prose, or `--bidi` for Hebrew and Arabic prose.
## Set FIGDRAW_BENCH_FALLBACK_FONT to a TTF file for an explicit fallback face.
## Pass `--wrap-only` to measure plain wrapping and skip the unbroken document.
## To include the companion HarfBuzzy checkout, add these options:
##   --excludePath:"$PWD/deps/harfbuzzy/src" --path:"$PWD/../harfbuzzy/src"
##
## Set FIGDRAW_HYPHEN_PATTERNS to a hyph-utf8 `.pat.txt`, TeX, or LibreOffice
## `.dic` file to measure hyphenation with real language patterns; otherwise a
## small built-in pattern set is used. Plain wrapping also compiles against
## releases without paragraph styles, for before/after comparisons.

import std/[algorithm, monotimes, os, strformat, strutils, times]

import figdraw

const
  Samples = 7
  Width = 420.0'f32
  Words = [
    "typesetting", "balances", "the", "measure", "against", "word", "spacing", "so",
    "every", "line", "reads", "evenly", "and", "paragraphs", "keep", "a", "steady",
    "texture", "without", "rivers", "of", "white", "space", "running", "through",
    "columns", "hyphenation", "helps", "narrow", "justified", "settings", "most",
  ]

proc document(paragraphs, wordsPerParagraph: int): string =
  var seed = 17
  for paragraph in 0 ..< paragraphs:
    if paragraph > 0:
      result.add '\n'
    for word in 0 ..< wordsPerParagraph:
      if word > 0:
        result.add ' '
      seed = (seed * 1103515245 + 12345) and 0x7fffffff
      result.add Words[seed mod Words.len]
    result.add '.'

proc median(values: var seq[float]): float =
  values.sort()
  values[values.len div 2]

when compiles(ParagraphStyle()):
  import figdraw/common/hyphenation

  proc registerPatterns() =
    let path = getEnv("FIGDRAW_HYPHEN_PATTERNS")
    if path.len > 0:
      registerHyphenationPatterns("en", loadHyphenationPatterns(path))
      echo "patterns: ", path
    else:
      registerHyphenationPatterns(
        "en",
        parseTexHyphenationPatterns(
          "hy3ph he2n hena4 hen5at 1na n2at 1tio 2io o2n 1ti 1ty 3ing ty1p 1ces"
        ),
      )
      echo "patterns: built-in sample"

  proc modes(): seq[(string, ParagraphStyle)] =
    @[
      ("wrap", ParagraphStyle()),
      ("indents", ParagraphStyle(firstLineIndent: 24, headIndent: 12, tailIndent: 8)),
      ("justify greedy", ParagraphStyle(align: paJustify)),
      ("justify greedy + hyphenate", ParagraphStyle(align: paJustify, hyphenate: true)),
      ("justify optimal", ParagraphStyle(align: paJustify, lineBreaking: plbOptimal)),
      (
        "justify optimal + hyphenate",
        ParagraphStyle(align: paJustify, lineBreaking: plbOptimal, hyphenate: true),
      ),
    ]

  proc styled(font: FigFont, style: ParagraphStyle): FontStyle =
    fs(font, fill(rgba(0, 0, 0, 255)), style)

else:
  proc registerPatterns() =
    echo "patterns: unsupported by this FigDraw"

  proc modes(): seq[(string, int)] =
    @[("wrap", 0)]

  proc styled(font: FigFont, style: int): FontStyle =
    fs(font)

proc benchmark(
    backend: TextBackendKind, text: string, anywhere = false, wrapOnly = false
) =
  setTextBackend(backend)
  let
    typefaceId = loadTypeface("Ubuntu.ttf", readFile(figDataDir() / "Ubuntu.ttf"), TTF)
    kilobytes = text.len.float / 1024
    source = initUtf8Runes(text)
    run = StyledTextRun(
      byteEnd: uint32(text.len), runeEnd: uint32(source.len), styleId: TextStyleId(0)
    )
  var font = FigFont(typefaceId: typefaceId, size: 16, language: "en")
  let fallback = getEnv("FIGDRAW_BENCH_FALLBACK_FONT")
  if fallback.len > 0:
    font.fallbackTypefaceIds.add loadTypeface(fallback, readFile(fallback), TTF)
  let selectedModes = modes()
  let modeCount = if wrapOnly: 1 else: selectedModes.len
  for index in 0 ..< modeCount:
    let (name, mode) = selectedModes[index]
    var style = mode
    when compiles(style.overflowWrap):
      if anywhere:
        style.overflowWrap = owAnywhere
    for api in ["spans", "source"]:
      var
        timings: seq[float]
        lines = 0
      for sample in 0 ..< Samples + 1:
        let start = getMonoTime()
        let arrangement =
          if api == "spans":
            typesetForMeasurement(
              rect(0, 0, Width, 100_000),
              [(styled(font, style), text)],
              Left,
              Top,
              minContent = false,
              wrap = true,
            )
          else:
            typesetSourceSpansForMeasurement(
              rect(0, 0, Width, 100_000),
              source,
              [run],
              [styled(font, style)],
              Left,
              Top,
              minContent = false,
              wrap = true,
            )
        let elapsed = (getMonoTime() - start).inNanoseconds.float / 1e6
        lines = arrangement.lines.len
        if sample > 0: # Discard the cache-warming run.
          timings.add elapsed
      let ms = timings.median()
      echo &"{$backend:>10} {api:<6} {name:<28} {ms:8.2f} ms {kilobytes / (ms / 1000):9.0f} KiB/s {lines:6} lines"

proc unbrokenText(bytes: int): string =
  ## Base64-like text without break opportunities, wrapped by emergency breaks.
  const Alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789"
  var seed = 29
  result = newStringOfCap(bytes)
  for _ in 0 ..< bytes:
    seed = (seed * 1103515245 + 12345) and 0x7fffffff
    result.add Alphabet[seed mod Alphabet.len]

when isMainModule:
  registerPatterns()
  var text = document(paragraphs = 200, wordsPerParagraph = 80)
  let
    args = commandLineParams()
    wrapOnly = "--wrap-only" in args
  if "--bidi" in args:
    text = text.multiReplace(
      ("typesetting", "שלום עולם"),
      ("balances", "مرحبا بالعالم"),
      ("steady", "Café (42)"),
    )
  elif "--mixed" in args:
    text = text.multiReplace(
      ("typesetting", "typographie"),
      ("balances", "équilibre"),
      ("steady", "régulier"),
      ("texture", "matière"),
    )
  echo &"document: {text.len div 1024} KiB, width {Width}"
  for backend in [TextBackendKind.Harfbuzzy, TextBackendKind.Pixie]:
    if textBackendAvailable(backend):
      benchmark(backend, text, wrapOnly = wrapOnly)
  if not wrapOnly:
    let unbroken = unbrokenText(108 * 1024)
    echo &"unbroken text: {unbroken.len div 1024} KiB, width {Width}"
    for backend in [TextBackendKind.Harfbuzzy, TextBackendKind.Pixie]:
      if textBackendAvailable(backend):
        benchmark(backend, unbroken, anywhere = true)
