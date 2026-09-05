import std/[options, os, sets, unittest]

from figdraw/common/typefaceinfos import readTypefaceNameInfo
import figdraw/extras/systemfonts_windows

suite "DirectWrite system-font provider":
  when defined(windows):
    const
      sansCandidates = ["Arial", "Liberation Sans", "DejaVu Sans"]
      boldCandidates = ["Arial Bold", "Liberation Sans Bold", "DejaVu Sans Bold"]

    test "returns a local regular face with an exact face index":
      let result = findNativeSystemTypefaceFile(sansCandidates)
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check match.path.fileExists()
      check match.faceIndex >= 0

    test "supports explicit full names and candidate fallback":
      let explicitFace = findNativeSystemTypefaceFile(boldCandidates)
      check explicitFace.available
      require explicitFace.match.isSome
      let boldMatch = explicitFace.match.get()
      check readTypefaceNameInfo(readFile(boldMatch.path), Natural(boldMatch.faceIndex)).bold

      let fallback = findNativeSystemTypefaceFile(
        ["FigDraw Missing Font 8E5269A4", "Arial", "Liberation Sans", "DejaVu Sans"]
      )
      check fallback.available
      check fallback.match.isSome

    test "does not accept an unrelated closest family":
      let result = findNativeSystemTypefaceFile(["FigDraw Missing Font 8E5269A4"])
      check result.available
      check result.match.isNone

    test "enumerates locally readable nonsimulated faces":
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
    test "is unavailable off Windows":
      let result = findNativeSystemTypefaceFile(["Arial"])
      check not result.available
      check result.match.isNone

    test "enumeration is unavailable off Windows":
      var available = true
      for info in nativeSystemTypefaces(available):
        discard info
        check false
      check not available
