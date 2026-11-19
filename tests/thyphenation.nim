import std/[os, strutils, tempfiles, unittest]

import figdraw/common/hyphenation

const LiangPatterns = "hy3ph he2n hena4 hen5at 1na n2at 1tio 2io o2n"

suite "hyphenation":
  setup:
    clearHyphenationPatterns()

  test "Liang patterns produce the TeXbook hyphenation":
    let patterns = parseTexHyphenationPatterns(LiangPatterns)
    check patterns.patternCount == 9
    check patterns.hyphenationPoints("hyphenation") == @[2, 6]
    check patterns.hyphenationPoints("Hyphenation") == @[2, 6]
    check patterns.hyphenationPoints("hy") == newSeq[int]()
    check patterns.hyphenationPoints("hyphen-ation") == newSeq[int]()

  test "minimum fragment lengths bound hyphen positions":
    var patterns = parseTexHyphenationPatterns(LiangPatterns, leftMin = 3, rightMin = 6)
    check patterns.hyphenationPoints("hyphenation") == newSeq[int]()
    patterns.leftMin = 2
    patterns.rightMin = 5
    check patterns.hyphenationPoints("hyphenation") == @[2, 6]

  test "TeX files read patterns, exceptions, and comments":
    let patterns = parseTexHyphenationPatterns(
      "% comment\n\\patterns{ % inline\n" & LiangPatterns & "\n}\n" &
        "\\hyphenation{ta-ble pro-ject}\n"
    )
    check patterns.patternCount == 9
    check patterns.hyphenationPoints("hyphenation") == @[2, 6]
    check patterns.hyphenationPoints("project") == @[3]
    check patterns.hyphenationPoints("table") == @[2]

  test "hyphen dictionaries read directives and Latin-1 patterns":
    let dictionary = parseHyphenDictionary(
      "ISO8859-1\nLEFTHYPHENMIN 1\nRIGHTHYPHENMIN 1\n% note\n" &
        LiangPatterns.replace(' ', '\n') & "\n\xe41b\nc1k/k=,1,1\nNEXTLEVEL\n1x\n"
    )
    check dictionary.leftMin == 1
    check dictionary.rightMin == 1
    check dictionary.patternCount == 10
    check dictionary.hyphenationPoints("hyphenation") == @[2, 6]
    check dictionary.hyphenationPoints("äb") == @[1]
    expect ValueError:
      discard parseHyphenDictionary("KOI8-R\n1a\n")

  test "registered languages fall back by subtag and default":
    registerHyphenationPatterns("en", parseTexHyphenationPatterns(LiangPatterns))
    check hasHyphenationPatterns("en-US")
    check hasHyphenationPatterns("EN_gb")
    check hyphenationPoints("en-US", "hyphenation") == @[2, 6]
    check not hasHyphenationPatterns("de")
    registerHyphenationPatterns("", parseTexHyphenationPatterns("1b"))
    check hyphenationPoints("de", "ababab") == @[3]
    unregisterHyphenationPatterns("")
    check not hasHyphenationPatterns("de")

  test "pattern directories register hyph-utf8 and dictionary files by language":
    let directory = createTempDir("figdraw", "hyphenation")
    defer:
      removeDir(directory)
    writeFile(directory / "hyph-en-us.pat.txt", LiangPatterns)
    writeFile(directory / "hyph-en-us.hyp.txt", "pro-ject\n")
    writeFile(directory / "hyph_de_DE.dic", "UTF-8\n1b\n")
    writeFile(directory / "README.txt", "not patterns")
    check patternFileLanguage("hyph-en-us.pat.txt") == "en-us"
    check patternFileLanguage("hyph_de_DE.dic") == "de-de"
    check patternFileLanguage("grammar.json") == ""
    let languages = registerHyphenationDirectory(directory)
    check languages.len == 2
    check "en-us" in languages
    check "de-de" in languages
    check hyphenationPoints("en-US", "project") == @[3]
    check hyphenationPoints("de", "ababab") == @[3]

  test "TeX files skip unrelated commands before pattern groups":
    let patterns = parseTexHyphenationPatterns(
      "\\relax\n\\lccode`\\'=`\\'\n\\begingroup\n\\patterns{\n" & LiangPatterns &
        "\n}\n\\endgroup\n\\hyphenation{pro-ject}\n"
    )
    check patterns.patternCount == 9
    check patterns.hyphenationPoints("hyphenation") == @[2, 6]
    check patterns.hyphenationPoints("project") == @[3]
    check parseTexHyphenationPatterns("\\patternsx{1a}\n\\patterns{1b}").patternCount ==
      1
    expect ValueError:
      discard parseTexHyphenationPatterns("\\patterns{hy3ph")

  test "byte-order marks and malformed directives keep defaults":
    let dictionary = parseHyphenDictionary(
      "\xEF\xBB\xBFUTF-8\nLEFTHYPHENMIN two\nRIGHTHYPHENMIN -1\n" &
        LiangPatterns.replace(' ', '\n')
    )
    check dictionary.leftMin == 2
    check dictionary.rightMin == 3
    check dictionary.hyphenationPoints("hyphenation") == @[2, 6]
    let tex = parseTexHyphenationPatterns("\xEF\xBB\xBF" & LiangPatterns)
    check tex.patternCount == 9

  test "pattern suffixes match regardless of case":
    let directory = createTempDir("figdraw", "hyphenation-case")
    defer:
      removeDir(directory)
    writeFile(directory / "HYPH-EN-US.PAT.TXT", LiangPatterns)
    writeFile(directory / "HYPH-EN-US.HYP.TXT", "pro-ject\n")
    let patterns = loadHyphenationPatterns(directory / "HYPH-EN-US.PAT.TXT")
    check patterns.patternCount == 9
    check patternFileLanguage("HYPH-EN-US.PAT.TXT") == "en-us"
