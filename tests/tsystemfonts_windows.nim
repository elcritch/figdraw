import std/[options, os, sets, unittest]

from figdraw/common/typefaceinfos import readTypefaceNameInfo
from figdraw/extras/systemfonttypes import SystemTypeface
import figdraw/extras/systemfonts_windows

suite "DirectWrite system-font provider":
  when defined(windows):
    const
      sansCandidates = ["Arial", "Liberation Sans", "DejaVu Sans"]
      boldCandidates = ["Arial Bold", "Liberation Sans Bold", "DejaVu Sans Bold"]

    test "returns a local regular face with an exact face index":
      let result = findNativeSystemTypeface(sansCandidates)
      check result.available
      require result.match.isSome
      let match = result.match.get()
      check match.file.path.fileExists()
      check match.file.faceIndex >= 0

    test "supports explicit full names and candidate fallback":
      let explicitFace = findNativeSystemTypeface(boldCandidates)
      check explicitFace.available
      require explicitFace.match.isSome
      let boldMatch = explicitFace.match.get()
      check readTypefaceNameInfo(
        readFile(boldMatch.file.path), Natural(boldMatch.file.faceIndex)
      ).bold

      let fallback = findNativeSystemTypeface(
        ["FigDraw Missing Font 8E5269A4", "Arial", "Liberation Sans", "DejaVu Sans"]
      )
      check fallback.available
      check fallback.match.isSome

    test "does not accept an unrelated closest family":
      let result = findNativeSystemTypeface(["FigDraw Missing Font 8E5269A4"])
      check result.available
      check result.match.isNone

    test "enumerates locally readable nonsimulated faces":
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
    test "is unavailable off Windows":
      let result = findNativeSystemTypeface(["Arial"])
      check not result.available
      check result.match.isNone

    test "enumeration is unavailable off Windows":
      var available = true
      for info in nativeSystemTypefaces(available):
        discard info
        check false
      check not available
