import std/[options, os, tempfiles, unicode, unittest]

import figdraw/common/typefaceinfos
import figdraw/extras/systemfonts

type NameEntry = tuple[id: int, text: string]

proc putUint16(data: var string, offset, value: int) =
  data[offset] = char((value shr 8) and 255)
  data[offset + 1] = char(value and 255)

proc putUint32(data: var string, offset, value: int) =
  data.putUint16(offset, value shr 16)
  data.putUint16(offset + 2, value and 65535)

proc utf16(text: string): string =
  for rune in text.runes:
    let codepoint = rune.int
    if codepoint <= 65535:
      result.add char(codepoint shr 8)
      result.add char(codepoint and 255)
    else:
      let
        highSurrogate = 0xd800 + ((codepoint - 0x10000) shr 10)
        lowSurrogate = 0xdc00 + ((codepoint - 0x10000) and 1023)
      result.add char(highSurrogate shr 8)
      result.add char(highSurrogate and 255)
      result.add char(lowSurrogate shr 8)
      result.add char(lowSurrogate and 255)

proc fontMetadata(
    family: string,
    style = "Regular",
    weight = 400,
    selection = 64,
    fullName = "",
    typographicFamily = "",
    typographicStyle = "",
    monospace = false,
): string =
  ## Minimal SFNT metadata fixture; deliberately contains no glyph outlines.
  var names: seq[NameEntry] = @[(1, family), (2, style)]
  names.add(
    (
      4,
      if fullName.len > 0:
        fullName
      else:
        family & " " & style,
    )
  )
  if typographicFamily.len > 0:
    names.add((16, typographicFamily))
  if typographicStyle.len > 0:
    names.add((17, typographicStyle))

  var nameTable = newString(6 + names.len * 12)
  nameTable.putUint16(2, names.len)
  nameTable.putUint16(4, nameTable.len)
  var strings: string
  for index, entry in names:
    let
      encoded = utf16(entry.text)
      offset = 6 + index * 12
    nameTable.putUint16(offset, 3)
    nameTable.putUint16(offset + 2, 1)
    nameTable.putUint16(offset + 4, 0x0409)
    nameTable.putUint16(offset + 6, entry.id)
    nameTable.putUint16(offset + 8, encoded.len)
    nameTable.putUint16(offset + 10, strings.len)
    strings.add encoded
  nameTable.add strings

  var
    styleTable = newString(86)
    postTable = newString(16)
  styleTable.putUint16(4, weight)
  styleTable.putUint16(6, 5)
  styleTable.putUint16(62, selection)
  postTable.putUint32(12, ord(monospace))
  let tables = [("name", nameTable), ("OS/2", styleTable), ("post", postTable)]
  result = newString(12 + tables.len * 16)
  result.putUint32(0, 0x00010000)
  result.putUint16(4, tables.len)
  for index, table in tables:
    let offset = 12 + index * 16
    for tagIndex in 0 .. 3:
      result[offset + tagIndex] = table[0][tagIndex]
    result.putUint32(offset + 8, result.len)
    result.putUint32(offset + 12, table[1].len)
    result.add table[1]

suite "installed font metadata resolution":
  setup:
    let fixtureDir = createTempDir("figdraw-font-metadata-", "")
    refreshSystemFontMetadata()

  teardown:
    refreshSystemFontMetadata()
    removeDir(fixtureDir)

  test "family metadata overrides an unrelated filename":
    let path = fixtureDir / "MisleadingName-Bold.ttf"
    writeFile(path, fontMetadata("Fixture Sans"))
    check findSystemTypeface(["Fixture Sans"], [path]) == some(initSystemTypeface(path))
    check findSystemTypeface(["MisleadingName"], [path]).isNone

  test "related families cannot consume a regular family as a prefix":
    let path = fixtureDir / "regular.ttf"
    writeFile(path, fontMetadata("Fixture Sans"))
    for name in ["Fixture Sans CJK", "Fixture Sans Mono", "Fixture Sans Unknown"]:
      check findSystemTypeface([name], [path]).isNone

  test "unstyled family skips bold italic and oblique faces for the next fallback":
    let
      bold = fixtureDir / "bold.ttf"
      italic = fixtureDir / "italic.ttf"
      oblique = fixtureDir / "oblique.ttf"
      fallback = fixtureDir / "fallback.ttf"
    writeFile(
      bold, fontMetadata("Fixture Sans", "Bold", 700, 32, fullName = "Fixture Sans")
    )
    writeFile(
      italic, fontMetadata("Fixture Sans", "Italic", 400, 1, fullName = "Fixture Sans")
    )
    writeFile(
      oblique,
      fontMetadata("Fixture Sans", "Oblique", 400, 512, fullName = "Fixture Sans"),
    )
    writeFile(fallback, fontMetadata("Other Sans"))
    check findSystemTypeface(
      ["Fixture Sans", "Other Sans"], [bold, italic, oblique, fallback]
    ) == some(initSystemTypeface(fallback))

  test "missing bold and italic styles preserve explicit fallback order":
    let
      regular = fixtureDir / "regular.ttf"
      fallback = fixtureDir / "fallback.ttf"
    writeFile(regular, fontMetadata("Fixture Sans"))
    writeFile(fallback, fontMetadata("Other Sans"))
    for name in ["Fixture Sans Bold", "Fixture Sans Italic"]:
      check findSystemTypeface([name, "Other Sans"], [regular, fallback]) ==
        some(initSystemTypeface(fallback))

  test "explicit styles use the matching face even with opaque filenames":
    let
      regular = fixtureDir / "font-a.ttf"
      bold = fixtureDir / "font-b.ttf"
      italic = fixtureDir / "font-c.ttf"
    writeFile(regular, fontMetadata("Fixture Sans"))
    writeFile(bold, fontMetadata("Fixture Sans", "Bold", 700, 32))
    writeFile(italic, fontMetadata("Fixture Sans", "Italic", 400, 1))
    check findSystemTypeface(["Fixture Sans Bold"], [regular, italic, bold]) ==
      some(initSystemTypeface(bold))
    check findSystemTypeface(["Fixture Sans Italic"], [regular, bold, italic]) ==
      some(initSystemTypeface(italic))

  test "typographic family and subfamily retain semibold style":
    let path = fixtureDir / "font.ttf"
    writeFile(
      path,
      fontMetadata(
        "Fixture Sans SemiBold",
        "Regular",
        600,
        64,
        typographicFamily = "Fixture Sans",
        typographicStyle = "SemiBold",
      ),
    )
    check findSystemTypeface(["Fixture Sans SemiBold"], [path]) ==
      some(initSystemTypeface(path))
    check findSystemTypeface(["Fixture Sans"], [path]).isNone

  test "style words are matched exactly and combined styles require both traits":
    let path = fixtureDir / "bold.ttf"
    writeFile(path, fontMetadata("Fixture Sans", "Bold", 700, 32))
    for name in [
      "Fixture Sans SemiBold", "Fixture Sans NotBold", "Fixture Sans Bold Italic"
    ]:
      check findSystemTypeface([name], [path]).isNone

  test "regional collection family names remain distinct":
    let path = fixtureDir / "regional.ttf"
    writeFile(path, fontMetadata("Fixture Sans CJK JP"))
    check findSystemTypeface(["Fixture Sans CJK JP"], [path]) ==
      some(initSystemTypeface(path))
    check findSystemTypeface(["Fixture Sans CJK SC"], [path]).isNone
    check findSystemTypeface(["Fixture Sans"], [path]).isNone

  test "Unicode family names remain distinct":
    let path = fixtureDir / "unicode.ttf"
    writeFile(path, fontMetadata("明朝"))
    check findSystemTypeface(["明朝"], [path]) == some(initSystemTypeface(path))
    check findSystemTypeface(["黑体"], [path]).isNone

  test "matches in one directory do not depend on enumeration order":
    let
      first = fixtureDir / "a.ttf"
      second = fixtureDir / "z.ttf"
    writeFile(first, fontMetadata("Fixture Sans"))
    writeFile(second, fontMetadata("Fixture Sans"))
    let expected = some(initSystemTypeface(first))
    check findSystemTypeface(["Fixture Sans"], [first, second]) == expected
    check findSystemTypeface(["Fixture Sans"], [second, first]) == expected

  test "metadata is cached until explicit refresh":
    let path = fixtureDir / "font.ttf"
    writeFile(path, fontMetadata("First Family"))
    check findSystemTypeface(["First Family"], [path]) == some(initSystemTypeface(path))
    writeFile(path, fontMetadata("Second Family"))
    check findSystemTypeface(["First Family"], [path]).isSome
    check findSystemTypeface(["Second Family"], [path]).isNone
    refreshSystemFontMetadata()
    check findSystemTypeface(["Second Family"], [path]) == some(
      initSystemTypeface(path)
    )
    check findSystemTypeface(["First Family"], [path]).isNone

  test "caller directory precedence wins over alphabetical file order":
    let
      userDir = fixtureDir / "user"
      systemDir = fixtureDir / "system"
      userFont = userDir / "z.ttf"
      systemFont = systemDir / "a.ttf"
    createDir(userDir)
    createDir(systemDir)
    writeFile(userFont, fontMetadata("Fixture Sans"))
    writeFile(systemFont, fontMetadata("Fixture Sans"))
    check findSystemTypeface(
      ["Fixture Sans"], [userFont, systemFont], preserveInputOrder = true
    ) == some(initSystemTypeface(userFont))

  test "malformed metadata cannot fall back to the filename":
    let path = fixtureDir / "FixtureSans-Regular.ttf"
    writeFile(path, "invalid font data")
    check findSystemTypeface(["Fixture Sans"], [path]).isNone

  test "lightweight name metadata has a distinct result type":
    let info = readTypefaceNameInfo(fontMetadata("Fixture Sans"))
    check info.family == "Fixture Sans"
    check info.faceIndex == 0
    check info.regular

  test "lightweight name metadata rejects a standalone nonzero face":
    expect ValueError:
      discard readTypefaceNameInfo(fontMetadata("Fixture Sans"), faceIndex = 1)
