import ./systemfonttypes

when defined(windows):
  import std/[dynlib, options, os, sets, strutils, unicode]

  type
    HResult = int32
    ULong = uint32
    UInt32 = uint32
    WinBool = int32
    WideChar = uint16
    Guid {.bycopy.} = object
      data1: uint32
      data2: uint16
      data3: uint16
      data4: array[8, uint8]

    IDWriteFactory = object
      lpVtbl: ptr IDWriteFactoryVtbl

    IDWriteFontCollection = object
      lpVtbl: ptr IDWriteFontCollectionVtbl

    IDWriteFontFamily = object
      lpVtbl: ptr IDWriteFontFamilyVtbl

    IDWriteFont = object
      lpVtbl: ptr IDWriteFontVtbl

    IDWriteLocalizedStrings = object
      lpVtbl: ptr IDWriteLocalizedStringsVtbl

    IDWriteFontFace = object
      lpVtbl: ptr IDWriteFontFaceVtbl

    IDWriteFontFile = object
      lpVtbl: ptr IDWriteFontFileVtbl

    IDWriteFontFileLoader = object
      lpVtbl: ptr IDWriteFontFileLoaderVtbl

    IDWriteLocalFontFileLoader = object
      lpVtbl: ptr IDWriteLocalFontFileLoaderVtbl

    QueryInterfaceProc =
      proc(self: pointer, iid: ptr Guid, value: ptr pointer): HResult {.stdcall.}
    AddRefProc = proc(self: pointer): ULong {.stdcall.}
    ReleaseProc = proc(self: pointer): ULong {.stdcall.}
    DWriteCreateFactoryProc =
      proc(factoryType: cint, iid: ptr Guid, factory: ptr pointer): HResult {.stdcall.}

    IDWriteFactoryVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getSystemFontCollection: proc(
        self: pointer,
        collection: ptr ptr IDWriteFontCollection,
        checkForUpdates: WinBool,
      ): HResult {.stdcall.}

    IDWriteFontCollectionVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getFontFamilyCount: proc(self: pointer): UInt32 {.stdcall.}
      getFontFamily: proc(
        self: pointer, index: UInt32, family: ptr ptr IDWriteFontFamily
      ): HResult {.stdcall.}
      findFamilyName: proc(
        self: pointer, familyName: ptr WideChar, index: ptr UInt32, exists: ptr WinBool
      ): HResult {.stdcall.}
      getFontFromFontFace: pointer

    IDWriteFontFamilyVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getFontCollection: pointer
      getFontCount: proc(self: pointer): UInt32 {.stdcall.}
      getFont: proc(self: pointer, index: UInt32, font: ptr ptr IDWriteFont): HResult {.
        stdcall
      .}
      getFamilyNames:
        proc(self: pointer, names: ptr ptr IDWriteLocalizedStrings): HResult {.stdcall.}
      getFirstMatchingFont: pointer
      getMatchingFonts: pointer

    IDWriteFontVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getFontFamily: pointer
      getWeight: proc(self: pointer): cint {.stdcall.}
      getStretch: proc(self: pointer): cint {.stdcall.}
      getStyle: proc(self: pointer): cint {.stdcall.}
      isSymbolFont: pointer
      getFaceNames:
        proc(self: pointer, names: ptr ptr IDWriteLocalizedStrings): HResult {.stdcall.}
      getInformationalStrings: proc(
        self: pointer,
        stringId: cint,
        strings: ptr ptr IDWriteLocalizedStrings,
        exists: ptr WinBool,
      ): HResult {.stdcall.}
      getSimulations: proc(self: pointer): cint {.stdcall.}
      getMetrics: pointer
      hasCharacter: pointer
      createFontFace:
        proc(self: pointer, fontFace: ptr ptr IDWriteFontFace): HResult {.stdcall.}

    IDWriteLocalizedStringsVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getCount: proc(self: pointer): UInt32 {.stdcall.}
      findLocaleName: pointer
      getLocaleNameLength: pointer
      getLocaleName: pointer
      getStringLength:
        proc(self: pointer, index: UInt32, length: ptr UInt32): HResult {.stdcall.}
      getString: proc(
        self: pointer, index: UInt32, value: ptr WideChar, size: UInt32
      ): HResult {.stdcall.}

    IDWriteFontFaceVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getType: pointer
      getFiles: proc(
        self: pointer, numberOfFiles: ptr UInt32, fontFiles: ptr ptr IDWriteFontFile
      ): HResult {.stdcall.}
      getIndex: proc(self: pointer): UInt32 {.stdcall.}

    IDWriteFontFileVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      getReferenceKey:
        proc(self: pointer, key: ptr pointer, keySize: ptr UInt32): HResult {.stdcall.}
      getLoader:
        proc(self: pointer, loader: ptr ptr IDWriteFontFileLoader): HResult {.stdcall.}
      analyze: pointer

    IDWriteFontFileLoaderVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      createStreamFromKey: pointer

    IDWriteLocalFontFileLoaderVtbl = object
      queryInterface: QueryInterfaceProc
      addRef: AddRefProc
      release: ReleaseProc
      createStreamFromKey: pointer
      getFilePathLengthFromKey: proc(
        self: pointer, key: pointer, keySize: UInt32, length: ptr UInt32
      ): HResult {.stdcall.}
      getFilePathFromKey: proc(
        self: pointer, key: pointer, keySize: UInt32, path: ptr WideChar, size: UInt32
      ): HResult {.stdcall.}
      getLastWriteTimeFromKey: pointer

  const
    dwriteFactoryTypeShared = 0.cint
    dwriteFontWeightSemiLight = 350.cint
    dwriteFontWeightRegular = 400.cint
    dwriteFontStretchNormal = 5.cint
    dwriteFontStyleNormal = 0.cint
    dwriteInformationalStringWin32FamilyNames = 11.cint
    dwriteInformationalStringWin32SubfamilyNames = 12.cint
    dwriteInformationalStringTypographicFamilyNames = 13.cint
    dwriteInformationalStringTypographicSubfamilyNames = 14.cint
    dwriteInformationalStringFullName = 16.cint
    dwriteInformationalStringPostscriptName = 17.cint

    iidIDWriteFactory = Guid(
      data1: 0xB859EE5A'u32,
      data2: 0xD838'u16,
      data3: 0x4B5B'u16,
      data4: [0xA2'u8, 0xE8'u8, 0x1A'u8, 0xDC'u8, 0x7D'u8, 0x93'u8, 0xDB'u8, 0x48'u8],
    )
    iidIDWriteLocalFontFileLoader = Guid(
      data1: 0xB2D9F3EC'u32,
      data2: 0xC9FE'u16,
      data3: 0x4A11'u16,
      data4: [0xA2'u8, 0xEC'u8, 0xD8'u8, 0x62'u8, 0x08'u8, 0xF7'u8, 0xC0'u8, 0xA2'u8],
    )

  template succeeded(value: HResult): bool =
    value >= 0

  template release(value: untyped) =
    if value != nil:
      discard value.lpVtbl.release(cast[pointer](value))
      value = nil

  proc utf16(value: string): seq[WideChar] =
    for rune in value.runes:
      let codepoint = rune.int
      if codepoint <= 0xFFFF:
        result.add(WideChar(codepoint))
      else:
        let offset = codepoint - 0x10000
        result.add(WideChar(0xD800 + (offset shr 10)))
        result.add(WideChar(0xDC00 + (offset and 0x3FF)))
    result.add(0)

  proc utf8(value: openArray[WideChar]): string =
    var index = 0
    while index < value.len and value[index] != 0:
      var codepoint = value[index].int
      inc index
      if codepoint in 0xD800 .. 0xDBFF and index < value.len:
        let trail = value[index].int
        if trail in 0xDC00 .. 0xDFFF:
          codepoint = 0x10000 + ((codepoint - 0xD800) shl 10) + trail - 0xDC00
          inc index
      result.add($Rune(codepoint))

  proc normalizedName(value: string): string =
    for rune in value.runes:
      result.add($rune.toLower)

  proc containsName(strings: ptr IDWriteLocalizedStrings, requested: string): bool =
    if strings == nil:
      return false
    let requested = requested.normalizedName()
    for index in 0'u32 ..< strings.lpVtbl.getCount(cast[pointer](strings)):
      var length: UInt32
      if not succeeded(
        strings.lpVtbl.getStringLength(cast[pointer](strings), index, addr length)
      ):
        continue
      var buffer = newSeq[WideChar](length.int + 1)
      if succeeded(
        strings.lpVtbl.getString(
          cast[pointer](strings), index, addr buffer[0], length + 1
        )
      ) and buffer.utf8().normalizedName() == requested:
        return true

  proc firstString(strings: ptr IDWriteLocalizedStrings): string =
    if strings == nil or strings.lpVtbl.getCount(cast[pointer](strings)) == 0:
      return
    var length: UInt32
    if not succeeded(
      strings.lpVtbl.getStringLength(cast[pointer](strings), 0, addr length)
    ):
      return
    var buffer = newSeq[WideChar](length.int + 1)
    if succeeded(
      strings.lpVtbl.getString(cast[pointer](strings), 0, addr buffer[0], length + 1)
    ):
      result = buffer.utf8()

  proc informationalName(font: ptr IDWriteFont, stringId: cint): string =
    var
      strings: ptr IDWriteLocalizedStrings
      exists: WinBool
    if succeeded(
      font.lpVtbl.getInformationalStrings(
        cast[pointer](font), stringId, addr strings, addr exists
      )
    ) and exists != 0:
      result = strings.firstString()
    release(strings)

  proc fontHasInformationalName(
      font: ptr IDWriteFont, requested: string, stringIds: openArray[cint]
  ): bool =
    for stringId in stringIds:
      var
        strings: ptr IDWriteLocalizedStrings
        exists: WinBool
      if succeeded(
        font.lpVtbl.getInformationalStrings(
          cast[pointer](font), stringId, addr strings, addr exists
        )
      ) and exists != 0:
        result = strings.containsName(requested)
      release(strings)
      if result:
        return

  proc fontHasFaceName(font: ptr IDWriteFont, requested: string): bool =
    var names: ptr IDWriteLocalizedStrings
    if succeeded(font.lpVtbl.getFaceNames(cast[pointer](font), addr names)):
      result = names.containsName(requested)
    release(names)

  proc isRegularFont(font: ptr IDWriteFont): bool =
    let weight = font.lpVtbl.getWeight(cast[pointer](font))
    font.lpVtbl.getStretch(cast[pointer](font)) == dwriteFontStretchNormal and
      font.lpVtbl.getStyle(cast[pointer](font)) == dwriteFontStyleNormal and
      font.lpVtbl.getSimulations(cast[pointer](font)) == 0 and (
      weight == dwriteFontWeightRegular or
      (weight == dwriteFontWeightSemiLight and font.fontHasFaceName("Book"))
    )

  proc containsFamilyFaceName(
      familyNames, faceNames: ptr IDWriteLocalizedStrings, requested: string
  ): bool =
    if familyNames == nil or faceNames == nil:
      return false
    let requested = requested.normalizedName()
    for familyIndex in 0'u32 ..< familyNames.lpVtbl.getCount(cast[pointer](familyNames)):
      var familyLength: UInt32
      if not succeeded(
        familyNames.lpVtbl.getStringLength(
          cast[pointer](familyNames), familyIndex, addr familyLength
        )
      ):
        continue
      var familyBuffer = newSeq[WideChar](familyLength.int + 1)
      if not succeeded(
        familyNames.lpVtbl.getString(
          cast[pointer](familyNames),
          familyIndex,
          addr familyBuffer[0],
          familyLength + 1,
        )
      ):
        continue
      let familyName = familyBuffer.utf8()
      for faceIndex in 0'u32 ..< faceNames.lpVtbl.getCount(cast[pointer](faceNames)):
        var faceLength: UInt32
        if not succeeded(
          faceNames.lpVtbl.getStringLength(
            cast[pointer](faceNames), faceIndex, addr faceLength
          )
        ):
          continue
        var faceBuffer = newSeq[WideChar](faceLength.int + 1)
        if succeeded(
          faceNames.lpVtbl.getString(
            cast[pointer](faceNames), faceIndex, addr faceBuffer[0], faceLength + 1
          )
        ) and (familyName & " " & faceBuffer.utf8()).normalizedName() == requested:
          return true

  proc localTypefaceFile(font: ptr IDWriteFont): Option[SystemTypefaceFile] =
    var face: ptr IDWriteFontFace
    if not succeeded(font.lpVtbl.createFontFace(cast[pointer](font), addr face)) or
        face == nil:
      return
    defer:
      release(face)

    var fileCount: UInt32
    if not succeeded(face.lpVtbl.getFiles(cast[pointer](face), addr fileCount, nil)) or
        fileCount != 1:
      return

    var fontFile: ptr IDWriteFontFile
    if not succeeded(
      face.lpVtbl.getFiles(cast[pointer](face), addr fileCount, addr fontFile)
    ) or fontFile == nil or fileCount != 1:
      release(fontFile)
      return
    defer:
      release(fontFile)

    var
      key: pointer
      keySize: UInt32
      loader: ptr IDWriteFontFileLoader
    if not succeeded(
      fontFile.lpVtbl.getReferenceKey(cast[pointer](fontFile), addr key, addr keySize)
    ) or key == nil:
      return
    if not succeeded(fontFile.lpVtbl.getLoader(cast[pointer](fontFile), addr loader)) or
        loader == nil:
      release(loader)
      return
    defer:
      release(loader)

    var localLoader: ptr IDWriteLocalFontFileLoader
    if not succeeded(
      loader.lpVtbl.queryInterface(
        cast[pointer](loader),
        unsafeAddr iidIDWriteLocalFontFileLoader,
        cast[ptr pointer](addr localLoader),
      )
    ) or localLoader == nil:
      release(localLoader)
      return
    defer:
      release(localLoader)

    var pathLength: UInt32
    if not succeeded(
      localLoader.lpVtbl.getFilePathLengthFromKey(
        cast[pointer](localLoader), key, keySize, addr pathLength
      )
    ):
      return
    var path = newSeq[WideChar](pathLength.int + 1)
    if not succeeded(
      localLoader.lpVtbl.getFilePathFromKey(
        cast[pointer](localLoader), key, keySize, addr path[0], pathLength + 1
      )
    ):
      return

    let decodedPath = path.utf8()
    if decodedPath.len == 0 or not decodedPath.isAbsolute() or
        not decodedPath.fileExists():
      return
    try:
      var file: File
      if not open(file, decodedPath, fmRead):
        return
      close(file)
    except IOError, OSError:
      return
    result = some(
      SystemTypefaceFile(
        path: decodedPath, faceIndex: face.lpVtbl.getIndex(cast[pointer](face)).int
      )
    )

  proc typefaceInfo(
      font: ptr IDWriteFont, fallbackFamily: string
  ): Option[SystemTypefaceInfo] =
    if font.lpVtbl.getSimulations(cast[pointer](font)) != 0:
      return
    let file = font.localTypefaceFile()
    if file.isNone:
      return

    var faceNames: ptr IDWriteLocalizedStrings
    discard font.lpVtbl.getFaceNames(cast[pointer](font), addr faceNames)
    let fallbackSubfamily = faceNames.firstString()
    release(faceNames)

    let
      typographicFamily =
        font.informationalName(dwriteInformationalStringTypographicFamilyNames)
      win32Family = font.informationalName(dwriteInformationalStringWin32FamilyNames)
      typographicSubfamily =
        font.informationalName(dwriteInformationalStringTypographicSubfamilyNames)
      win32Subfamily =
        font.informationalName(dwriteInformationalStringWin32SubfamilyNames)
    result = some(
      SystemTypefaceInfo(
        file: file.get(),
        family:
          if typographicFamily.len > 0:
            typographicFamily
          elif win32Family.len > 0:
            win32Family
          else:
            fallbackFamily,
        subfamily:
          if typographicSubfamily.len > 0:
            typographicSubfamily
          elif win32Subfamily.len > 0:
            win32Subfamily
          else:
            fallbackSubfamily,
        fullName: font.informationalName(dwriteInformationalStringFullName),
        postScriptName: font.informationalName(dwriteInformationalStringPostscriptName),
      )
    )

  proc familyTypefaces(
      collection: ptr IDWriteFontCollection, familyIndex: UInt32
  ): seq[SystemTypefaceInfo] =
    var family: ptr IDWriteFontFamily
    if not succeeded(
      collection.lpVtbl.getFontFamily(
        cast[pointer](collection), familyIndex, addr family
      )
    ) or family == nil:
      release(family)
      return
    defer:
      release(family)

    var familyNames: ptr IDWriteLocalizedStrings
    discard family.lpVtbl.getFamilyNames(cast[pointer](family), addr familyNames)
    let fallbackFamily = familyNames.firstString()
    release(familyNames)

    for fontIndex in 0'u32 ..< family.lpVtbl.getFontCount(cast[pointer](family)):
      var font: ptr IDWriteFont
      if not succeeded(
        family.lpVtbl.getFont(cast[pointer](family), fontIndex, addr font)
      ) or font == nil:
        release(font)
        continue
      let info = font.typefaceInfo(fallbackFamily)
      release(font)
      if info.isSome:
        result.add info.get()

  iterator nativeSystemTypefaces*(available: var bool): SystemTypefaceInfo =
    ## Enumerates locally readable, nonsimulated DirectWrite faces.
    var seen = initHashSet[(string, int)]()
    block provider:
      let dwriteLibrary = loadLib("dwrite.dll")
      if dwriteLibrary == nil:
        available = false
        break provider
      defer:
        unloadLib(dwriteLibrary)
      let dWriteCreateFactory =
        cast[DWriteCreateFactoryProc](dwriteLibrary.symAddr("DWriteCreateFactory"))
      if dWriteCreateFactory == nil:
        available = false
        break provider

      var factory: ptr IDWriteFactory
      if not succeeded(
        dWriteCreateFactory(
          dwriteFactoryTypeShared,
          unsafeAddr iidIDWriteFactory,
          cast[ptr pointer](addr factory),
        )
      ) or factory == nil:
        release(factory)
        available = false
        break provider
      defer:
        release(factory)

      var collection: ptr IDWriteFontCollection
      if not succeeded(
        factory.lpVtbl.getSystemFontCollection(
          cast[pointer](factory), addr collection, 0
        )
      ) or collection == nil:
        release(collection)
        available = false
        break provider
      defer:
        release(collection)
      available = true

      for familyIndex in 0'u32 ..<
          collection.lpVtbl.getFontFamilyCount(cast[pointer](collection)):
        for info in collection.familyTypefaces(familyIndex):
          let identity =
            (info.file.path.toLowerAscii().replace('\\', '/'), info.file.faceIndex)
          if identity notin seen:
            seen.incl(identity)
            yield info

  proc regularFamilyTypeface(
      collection: ptr IDWriteFontCollection, familyIndex: UInt32
  ): Option[SystemTypefaceFile] =
    var family: ptr IDWriteFontFamily
    if not succeeded(
      collection.lpVtbl.getFontFamily(
        cast[pointer](collection), familyIndex, addr family
      )
    ) or family == nil:
      release(family)
      return
    defer:
      release(family)

    # Avoid GetFirstMatchingFont: it deliberately returns a closest style when
    # the requested regular face is absent.
    for desiredWeight in [dwriteFontWeightRegular, dwriteFontWeightSemiLight]:
      for index in 0'u32 ..< family.lpVtbl.getFontCount(cast[pointer](family)):
        var font: ptr IDWriteFont
        if not succeeded(family.lpVtbl.getFont(cast[pointer](family), index, addr font)) or
            font == nil:
          release(font)
          continue
        if font.isRegularFont() and
            font.lpVtbl.getWeight(cast[pointer](font)) == desiredWeight:
          result = font.localTypefaceFile()
        release(font)
        if result.isSome:
          return

  proc explicitTypeface(
      collection: ptr IDWriteFontCollection, requested: string
  ): Option[SystemTypefaceFile] =
    var bookFallback: Option[SystemTypefaceFile]
    for familyIndex in 0'u32 ..<
        collection.lpVtbl.getFontFamilyCount(cast[pointer](collection)):
      var family: ptr IDWriteFontFamily
      if not succeeded(
        collection.lpVtbl.getFontFamily(
          cast[pointer](collection), familyIndex, addr family
        )
      ) or family == nil:
        release(family)
        continue
      var familyNames: ptr IDWriteLocalizedStrings
      if not succeeded(
        family.lpVtbl.getFamilyNames(cast[pointer](family), addr familyNames)
      ):
        release(familyNames)
      for fontIndex in 0'u32 ..< family.lpVtbl.getFontCount(cast[pointer](family)):
        var font: ptr IDWriteFont
        if not succeeded(
          family.lpVtbl.getFont(cast[pointer](family), fontIndex, addr font)
        ) or font == nil:
          release(font)
          continue
        if font.lpVtbl.getSimulations(cast[pointer](font)) != 0:
          release(font)
          continue
        var faceNames: ptr IDWriteLocalizedStrings
        discard font.lpVtbl.getFaceNames(cast[pointer](font), addr faceNames)
        let explicitNameMatches =
          font.fontHasInformationalName(
            requested,
            [dwriteInformationalStringFullName, dwriteInformationalStringPostscriptName],
          ) or containsFamilyFaceName(familyNames, faceNames, requested)
        let familyNameMatches =
          font.isRegularFont() and
          font.fontHasInformationalName(
            requested,
            [
              dwriteInformationalStringWin32FamilyNames,
              dwriteInformationalStringTypographicFamilyNames,
            ],
          )
        release(faceNames)
        if explicitNameMatches:
          result = font.localTypefaceFile()
        elif familyNameMatches:
          let candidate = font.localTypefaceFile()
          if font.lpVtbl.getWeight(cast[pointer](font)) == dwriteFontWeightRegular:
            result = candidate
          elif bookFallback.isNone:
            bookFallback = candidate
        release(font)
        if result.isSome:
          break
      release(familyNames)
      release(family)
      if result.isSome:
        return
    result = bookFallback

  proc findNativeSystemTypefaceFile*(
      names: openArray[string]
  ): SystemFontProviderResult =
    ## Resolves an installed DirectWrite face to its local file and face index.
    let dwriteLibrary = loadLib("dwrite.dll")
    if dwriteLibrary == nil:
      return unavailableSystemFontProvider()
    defer:
      unloadLib(dwriteLibrary)
    let dWriteCreateFactory =
      cast[DWriteCreateFactoryProc](dwriteLibrary.symAddr("DWriteCreateFactory"))
    if dWriteCreateFactory == nil:
      return unavailableSystemFontProvider()

    var factory: ptr IDWriteFactory
    if not succeeded(
      dWriteCreateFactory(
        dwriteFactoryTypeShared,
        unsafeAddr iidIDWriteFactory,
        cast[ptr pointer](addr factory),
      )
    ) or factory == nil:
      release(factory)
      return unavailableSystemFontProvider()
    defer:
      release(factory)

    var collection: ptr IDWriteFontCollection
    if not succeeded(
      factory.lpVtbl.getSystemFontCollection(cast[pointer](factory), addr collection, 0)
    ) or collection == nil:
      release(collection)
      return unavailableSystemFontProvider()
    defer:
      release(collection)

    for requested in names:
      if requested.len == 0:
        continue
      var
        familyIndex: UInt32
        exists: WinBool
        wideName = requested.utf16()
      if succeeded(
        collection.lpVtbl.findFamilyName(
          cast[pointer](collection), addr wideName[0], addr familyIndex, addr exists
        )
      ) and exists != 0:
        let match = collection.regularFamilyTypeface(familyIndex)
        if match.isSome:
          return systemFontProviderMatch(match)

      let match = collection.explicitTypeface(requested)
      if match.isSome:
        return systemFontProviderMatch(match)

    systemFontProviderMatch(none(SystemTypefaceFile))

else:
  iterator nativeSystemTypefaces*(available: var bool): SystemTypefaceInfo =
    ## DirectWrite enumeration is unavailable off Windows.
    available = false

  proc findNativeSystemTypefaceFile*(
      names: openArray[string]
  ): SystemFontProviderResult =
    ## The DirectWrite system font provider is unavailable off Windows.
    discard names
    unavailableSystemFontProvider()
