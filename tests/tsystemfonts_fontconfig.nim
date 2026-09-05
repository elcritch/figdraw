import std/[options, os, sets, unittest]

when defined(linux) or defined(freebsd):
  from figdraw/common/typefaceinfos import readTypefaceNameInfo
  import figdraw/extras/systemfonts_fontconfig

  suite "Fontconfig system-font provider":
    test "returns a local regular face with an exact face index":
      let result = findNativeSystemTypefaceFile(
        ["DejaVu Sans", "Noto Sans", "Liberation Sans", "Ubuntu"]
      )
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check match.path.isAbsolute()
      check match.path.fileExists()
      check match.faceIndex >= 0

    test "respects candidate fallback order":
      let result = findNativeSystemTypefaceFile(
        [
          "FigDraw Font That Cannot Possibly Be Installed 3A916EC4", "DejaVu Sans",
          "Noto Sans", "Liberation Sans", "Ubuntu",
        ]
      )
      check result.available
      check result.match.isSome

    test "returns the requested explicit style":
      let result = findNativeSystemTypefaceFile(
        ["DejaVu Sans Bold", "Noto Sans Bold", "Liberation Sans Bold"]
      )
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check readTypefaceNameInfo(readFile(match.path), Natural(match.faceIndex)).bold

    test "rejects Fontconfig's closest match":
      let result = findNativeSystemTypefaceFile(
        ["FigDraw Font That Cannot Possibly Be Installed 9E548A3C"]
      )
      check result.available
      check result.match.isNone

    test "enumerates unique locally readable faces":
      var
        available = false
        identities = initHashSet[(string, int)]()
      for info in nativeSystemTypefaces(available):
        let identity = (info.file.path, info.file.faceIndex)
        check info.file.path.isAbsolute()
        check info.file.path.fileExists()
        check identity notin identities
        identities.incl(identity)
      check available
      check identities.len > 0
else:
  suite "Fontconfig system-font provider":
    test "is only exercised on Fontconfig platforms":
      check true
