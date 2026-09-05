import std/[options, os, unittest]

when defined(macosx):
  from figdraw/common/typefaceinfos import readTypefaceNameInfo
  import figdraw/extras/systemfonts_macos

  suite "Core Text system-font provider":
    test "returns a local regular face with an exact face index":
      let result = findNativeSystemTypefaceFile(["Helvetica"])
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check match.path.fileExists()
      check match.faceIndex >= 0

    test "supports explicit full names and candidate fallback":
      let explicitFace = findNativeSystemTypefaceFile(["Helvetica Bold"])
      check explicitFace.available
      require explicitFace.match.isSome
      let boldMatch = explicitFace.match.get()
      check readTypefaceNameInfo(readFile(boldMatch.path), Natural(boldMatch.faceIndex)).bold

      let fallback =
        findNativeSystemTypefaceFile(["FigDraw Missing Font 8E5269A4", "Helvetica"])
      check fallback.available
      check fallback.match.isSome

    test "does not accept an unrelated Core Text fallback":
      let result = findNativeSystemTypefaceFile(["FigDraw Missing Font 8E5269A4"])
      check result.available
      check result.match.isNone
else:
  suite "Core Text system-font provider":
    test "is only exercised on macOS":
      check true
