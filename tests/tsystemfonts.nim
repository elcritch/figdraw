import std/[options, os, sets, strutils, unittest]

import figdraw/common/fonttypes

when defined(useNativeDynlib):
  import figdraw/dynlib
  from figdraw/extras/systemfonts import
    systemDefaultFontNames, findSystemFontFile, findSystemTypefaceFile,
    refreshSystemFontMetadata, fontNameMatchScore, systemTypefaces, SystemTypefaceQuery,
    sfrMono
else:
  import figdraw

suite "system fonts":
  test "platform default font names are listed by role":
    let
      sans = systemDefaultFontNames()
      mono = systemDefaultFontNames(sfrMono)

    when defined(windows):
      check sans == @["Segoe UI", "Arial", "Tahoma", "Verdana"]
      check mono == @["Cascadia Mono", "Consolas", "Courier New"]
    elif defined(macosx):
      check sans == @["Helvetica", "Arial", "SFNS"]
      check mono == @["Menlo", "SF Mono", "Monaco"]
    elif defined(posix):
      check sans == @["Noto Sans", "DejaVu Sans", "Liberation Sans", "Ubuntu"]
      check mono ==
        @["Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono", "Ubuntu Mono"]
    else:
      check sans.len == 0
      check mono.len == 0

  test "system font dirs are discoverable":
    let dirs = systemFontDirs()
    check dirs.len > 0

  test "system font files are discoverable":
    let fonts = systemFontFiles()
    check fonts.len > 0
    for font in fonts:
      check font.splitFile.ext.toLowerAscii() in fonttypes.supportedFontFileExtensions()

  test "system typeface iterator returns unique readable face identities":
    var
      identities = initHashSet[(string, int)]()
      count = 0
    for info in systemTypefaces():
      let identity = (info.file.path, info.file.faceIndex)
      check info.file.path.isAbsolute()
      check info.file.path.fileExists()
      check info.file.faceIndex >= 0
      check identity notin identities
      identities.incl(identity)
      inc count
    check count > 0

  test "system typeface queries are strict filters":
    var
      family: string
      subfamily: string
    for info in systemTypefaces():
      if info.family.len > 0 and info.subfamily.len > 0 and
          info.family.allCharsInSet({'\x20' .. '\x7e'}) and
          info.subfamily.allCharsInSet({'\x20' .. '\x7e'}):
        family = info.family
        subfamily = info.subfamily
        break
    require family.len > 0

    var matchingCount = 0
    for info in systemTypefaces(SystemTypefaceQuery(family: family.toUpperAscii())):
      check info.family.toLowerAscii() == family.toLowerAscii()
      inc matchingCount
    check matchingCount > 0

    var styleMatchingCount = 0
    for info in systemTypefaces(
      SystemTypefaceQuery(
        family: "-" & family.replace(" ", "_") & ".",
        subfamily: "-" & subfamily.replace(" ", "_") & ".",
      )
    ):
      check info.family.toLowerAscii() == family.toLowerAscii()
      check info.subfamily.toLowerAscii() == subfamily.toLowerAscii()
      inc styleMatchingCount
    check styleMatchingCount > 0

    for info in systemTypefaces(
      SystemTypefaceQuery(family: "FigDraw Missing Font 2D601F0A")
    ):
      discard info
      check false

  test "system typeface iterator does not swallow consumer exceptions":
    expect ValueError:
      for info in systemTypefaces():
        discard info
        raise newException(ValueError, "consumer exception")

  test "family lookup rejects related and styled font filenames":
    let font = findSystemFontFile(
      ["Noto Sans", "DejaVu Sans"],
      [
        "/fonts/NotoSansCJK-Bold.ttc", "/fonts/NotoSansMono-Regular.ttf",
        "/fonts/NotoSans-Italic.ttf", "/fonts/DejaVuSans.ttf",
      ],
    )
    check font == "/fonts/DejaVuSans.ttf"

  test "family lookup prefers a regular face over later fallbacks":
    let font = findSystemFontFile(
      ["Noto Sans", "DejaVu Sans"],
      [
        "/fonts/NotoSansCJK-Bold.ttc", "/fonts/NotoSans-Regular.ttf",
        "/fonts/DejaVuSans.ttf",
      ],
    )
    check font == "/fonts/NotoSans-Regular.ttf"

  test "family lookup supports conventional regular filename aliases":
    check findSystemFontFile(["Ubuntu"], ["/fonts/Ubuntu-R.ttf"]) ==
      "/fonts/Ubuntu-R.ttf"

  test "filename requests retain exact matching":
    check findSystemFontFile(
      ["Noto Sans.ttf"], ["/fonts/NotoSans.otf", "/fonts/NotoSans.ttf"]
    ) == "/fonts/NotoSans.ttf"

  test "explicit style requests match only that style":
    check findSystemFontFile(
      ["Noto Sans Bold"], ["/fonts/NotoSans-Regular.ttf", "/fonts/NotoSans-Bold.ttf"]
    ) == "/fonts/NotoSans-Bold.ttf"

  test "collection face scoring excludes bold before a regular face":
    check fontNameMatchScore("PT Sans", "PT Sans Bold") == -1
    check fontNameMatchScore("PT Sans", "PT Sans Regular") == 1

  test "OpenType metadata selects a regular collection face independent of filename":
    let
      tempDir = getTempDir() / "figdraw-system-font-metadata-test"
      sourcePath = getCurrentDir() / "deps/pixie/tests/fonts/PTSans.ttc"
      collectionPath = tempDir / "unrelated-name.ttc"
    if not dirExists(tempDir):
      createDir(tempDir)
    defer:
      refreshSystemFontMetadata()
      if dirExists(tempDir):
        removeDir(tempDir)

    var data = readFile(sourcePath)
    swap(data[12], data[16])
    swap(data[13], data[17])
    swap(data[14], data[18])
    swap(data[15], data[19])
    writeFile(collectionPath, data)
    refreshSystemFontMetadata()

    let match = findSystemTypefaceFile(["PT Sans"], [collectionPath])
    require match.isSome
    check match.get().path == collectionPath
    check match.get().faceIndex == 1

  test "regional family aliases resolve their base collection":
    check findSystemFontFile(["PingFang SC"], ["/fonts/PingFang.ttc"]) ==
      "/fonts/PingFang.ttc"
    check findSystemFontFile(["Noto Sans"], ["/fonts/NotoSansCJK-Bold.ttc"]).len == 0

  when defined(windows):
    test "find common windows system font":
      let font =
        findSystemFontFile(["Arial", "Segoe UI", "Tahoma", "Verdana", "Calibri"])
      check font.len > 0
      check fileExists(font)
  elif defined(macosx):
    test "find common macos system font":
      let font = findSystemFontFile(["Helvetica", "Arial", "Menlo", "SFNS"])
      check font.len > 0
      check fileExists(font)

    test "prefer exact macos font names over partial matches":
      let
        helvetica = findSystemFontFile(["Helvetica"])
        timesNewRoman = findSystemFontFile(["Times New Roman"])
      check helvetica.extractFilename == "Helvetica.ttc"
      check timesNewRoman.extractFilename == "Times New Roman.ttf"
  elif defined(linux) or defined(bsd):
    test "detect display server from environment":
      let oldWayland = getEnv("WAYLAND_DISPLAY", "")
      let oldDisplay = getEnv("DISPLAY", "")
      let hadWayland = existsEnv("WAYLAND_DISPLAY")
      let hadDisplay = existsEnv("DISPLAY")

      putEnv("WAYLAND_DISPLAY", "wayland-1")
      putEnv("DISPLAY", "")
      check detectDisplayServer() == dsWayland

      putEnv("WAYLAND_DISPLAY", "")
      putEnv("DISPLAY", ":0")
      check detectDisplayServer() == dsX11

      if hadWayland:
        putEnv("WAYLAND_DISPLAY", oldWayland)
      else:
        delEnv("WAYLAND_DISPLAY")

      if hadDisplay:
        putEnv("DISPLAY", oldDisplay)
      else:
        delEnv("DISPLAY")

    test "linux/freebsd supports wayland and x11 directory resolution":
      let x11Dirs = systemFontDirs(dsX11)
      let waylandDirs = systemFontDirs(dsWayland)
      check x11Dirs.len > 0
      check waylandDirs.len > 0

    test "find common linux/freebsd system font":
      let font = findSystemFontFile(
        ["DejaVu Sans.ttf", "Noto Sans", "Liberation Sans", "Ubuntu"]
      )
      check font.len > 0
      check fileExists(font)
  else:
    test "unsupported platform":
      check true
