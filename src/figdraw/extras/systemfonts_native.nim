import ./systemfonttypes

when defined(windows):
  import ./systemfonts_windows as platformSystemFonts
elif defined(macosx):
  import ./systemfonts_macos as platformSystemFonts
elif defined(linux) or defined(freebsd):
  import ./systemfonts_fontconfig as platformSystemFonts

proc findNativeSystemTypefaceFile*(names: openArray[string]): SystemFontProviderResult =
  ## Dispatches installed-font matching to the host platform font service.
  when declared(platformSystemFonts):
    platformSystemFonts.findNativeSystemTypefaceFile(names)
  else:
    unavailableSystemFontProvider()

iterator nativeSystemTypefaces*(available: var bool): SystemTypefaceInfo =
  ## Enumerates local faces from the host platform font service.
  when declared(platformSystemFonts):
    for info in platformSystemFonts.nativeSystemTypefaces(available):
      yield info
  else:
    available = false
