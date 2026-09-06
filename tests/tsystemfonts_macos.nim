import std/[options, os, sets, unittest]

when defined(macosx):
  from figdraw/common/typefaceinfos import readTypefaceNameInfo
  from figdraw/extras/systemfonttypes import SystemTypeface, SystemTypefaceInfo
  import figdraw/extras/systemfonts_macos

  suite "Core Text system-font provider":
    test "returns a local regular face with an exact face index":
      let result = findNativeSystemTypeface(["Helvetica"])
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check match.file.path.fileExists()
      check match.file.faceIndex >= 0

    test "supports explicit full names and candidate fallback":
      let explicitFace = findNativeSystemTypeface(["Helvetica Bold"])
      check explicitFace.available
      require explicitFace.match.isSome
      let boldMatch = explicitFace.match.get()
      check readTypefaceNameInfo(
        readFile(boldMatch.file.path), Natural(boldMatch.file.faceIndex)
      ).bold

      let fallback =
        findNativeSystemTypeface(["FigDraw Missing Font 8E5269A4", "Helvetica"])
      check fallback.available
      check fallback.match.isSome

    test "does not accept an unrelated Core Text fallback":
      let result = findNativeSystemTypeface(["FigDraw Missing Font 8E5269A4"])
      check result.available
      check result.match.isNone

    test "enumerates owned local faces with unique identities":
      var
        available = false
        identities = initHashSet[SystemTypeface]()
        checkedCollectionFace = false
      for info in nativeSystemTypefaces(available):
        check info.typeface.file.path.fileExists()
        check info.typeface notin identities
        identities.incl(info.typeface)
        if not checkedCollectionFace and info.typeface.file.faceIndex > 0:
          let parsed = readTypefaceNameInfo(
            readFile(info.typeface.file.path), Natural(info.typeface.file.faceIndex)
          )
          check parsed.postScriptName == info.postScriptName
          checkedCollectionFace = true
      check available
      check identities.len > 0
      check checkedCollectionFace

    test "named variable instances round-trip through exact lookup":
      var
        available = false
        namedInstance: SystemTypefaceInfo
      for info in nativeSystemTypefaces(available):
        if info.typeface.variations.len > 0 and info.postScriptName.len > 0:
          namedInstance = info
          break
      check available
      if namedInstance.postScriptName.len > 0:
        let result = findNativeSystemTypeface([namedInstance.postScriptName])
        check result.available
        require result.match.isSome
        check result.match.get() == namedInstance.typeface
else:
  suite "Core Text system-font provider":
    test "is only exercised on macOS":
      check true
