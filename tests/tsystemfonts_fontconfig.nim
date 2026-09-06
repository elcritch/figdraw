import std/[options, os, sets, unittest]

when defined(linux) or defined(freebsd):
  from figdraw/common/typefaceinfos import readTypefaceNameInfo
  from figdraw/extras/systemfonttypes import SystemTypeface
  import figdraw/extras/systemfonts_fontconfig

  suite "Fontconfig system-font provider":
    test "returns a local regular face with an exact face index":
      let result = findNativeSystemTypeface(
        ["DejaVu Sans", "Noto Sans", "Liberation Sans", "Ubuntu"]
      )
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check match.file.path.isAbsolute()
      check match.file.path.fileExists()
      check match.file.faceIndex >= 0

    test "respects candidate fallback order":
      let result = findNativeSystemTypeface(
        [
          "FigDraw Font That Cannot Possibly Be Installed 3A916EC4", "DejaVu Sans",
          "Noto Sans", "Liberation Sans", "Ubuntu",
        ]
      )
      check result.available
      check result.match.isSome

    test "returns the requested explicit style":
      let result = findNativeSystemTypeface(
        ["DejaVu Sans Bold", "Noto Sans Bold", "Liberation Sans Bold"]
      )
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check readTypefaceNameInfo(
        readFile(match.file.path), Natural(match.file.faceIndex)
      ).bold

    test "rejects Fontconfig's closest match":
      let result = findNativeSystemTypeface(
        ["FigDraw Font That Cannot Possibly Be Installed 9E548A3C"]
      )
      check result.available
      check result.match.isNone

    test "enumerates unique locally readable faces":
      var
        available = false
        identities = initHashSet[SystemTypeface]()
      for info in nativeSystemTypefaces(available):
        check info.typeface.file.path.isAbsolute()
        check info.typeface.file.path.fileExists()
        check info.typeface notin identities
        identities.incl(info.typeface)
      check available
      check identities.len > 0
else:
  suite "Fontconfig system-font provider":
    test "is only exercised on Fontconfig platforms":
      check true
