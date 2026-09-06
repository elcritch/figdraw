## Native installed-font lookup for macOS.
##
## Core Text may substitute a fallback when asked to create an unknown font.
## Every result is therefore checked against the requested family, full, or
## PostScript name before its file URL is accepted.

import std/[options, os, unicode]

from ../common/fonttypes import FontVariation, fontVariation

import ./systemfonttypes

{.passL: "-framework CoreFoundation".}
{.passL: "-framework CoreText".}

type
  CFIndex = clong
  CFStringEncoding = uint32
  CFStringRef = pointer
  CFURLRef = pointer
  CFArrayRef = pointer
  CFDictionaryRef = pointer
  CFNumberRef = pointer
  CFNumberType = CFIndex
  CTFontRef = pointer
  CTFontDescriptorRef = pointer
  CTFontOptions = uint32

const
  kCFStringEncodingUTF8 = 0x08000100'u32
  kCFNumberSInt64Type = CFNumberType(4)
  kCFNumberFloat64Type = CFNumberType(6)
  kCTFontOptionsPreventAutoActivation = 1'u32
  kCTFontOptionsPreventAutoDownload = 2'u32
  kCTFontTraitItalic = 1'u32
  kCTFontTraitBold = 2'u32
  maxFileSystemPath = 32 * 1024

var
  kCTFontURLAttribute {.importc, header: "<CoreText/CoreText.h>".}: CFStringRef
  kCTFontNameAttribute {.importc, header: "<CoreText/CoreText.h>".}: CFStringRef
  kCTFontStyleNameKey {.importc, header: "<CoreText/CoreText.h>".}: CFStringRef

{.push cdecl, importc, header: "<CoreFoundation/CoreFoundation.h>".}
proc CFRelease(value: pointer)
proc CFStringCreateWithBytes(
  allocator, bytes: pointer,
  byteCount: CFIndex,
  encoding: CFStringEncoding,
  isExternalRepresentation: uint8,
): CFStringRef

proc CFStringGetLength(value: CFStringRef): CFIndex
proc CFStringGetMaximumSizeForEncoding(
  length: CFIndex, encoding: CFStringEncoding
): CFIndex

proc CFStringGetCString(
  value: CFStringRef, buffer: cstring, bufferSize: CFIndex, encoding: CFStringEncoding
): uint8

proc CFArrayGetCount(value: CFArrayRef): CFIndex
proc CFArrayGetValueAtIndex(value: CFArrayRef, index: CFIndex): pointer
proc CFDictionaryGetCount(value: CFDictionaryRef): CFIndex
proc CFDictionaryGetKeysAndValues(
  value: CFDictionaryRef, keys, values: ptr UncheckedArray[pointer]
)

proc CFNumberGetValue(
  number: CFNumberRef, numberType: CFNumberType, value: pointer
): uint8

proc CFURLGetFileSystemRepresentation(
  url: CFURLRef, resolveAgainstBase: uint8, buffer: ptr uint8, maxBufferLength: CFIndex
): uint8

{.pop.}

{.push cdecl, importc, header: "<CoreText/CoreText.h>".}
proc CTFontCreateWithNameAndOptions(
  name: CFStringRef, size: cdouble, matrix: pointer, options: CTFontOptions
): CTFontRef

proc CTFontCopyPostScriptName(font: CTFontRef): CFStringRef
proc CTFontCopyFamilyName(font: CTFontRef): CFStringRef
proc CTFontCopyFullName(font: CTFontRef): CFStringRef
proc CTFontCopyName(font: CTFontRef, nameKey: CFStringRef): CFStringRef
proc CTFontGetSymbolicTraits(font: CTFontRef): uint32
proc CTFontCopyVariation(font: CTFontRef): CFDictionaryRef
proc CTFontCopyAttribute(font: CTFontRef, attribute: CFStringRef): pointer
proc CTFontDescriptorCopyAttribute(
  descriptor: CTFontDescriptorRef, attribute: CFStringRef
): pointer

proc CTFontManagerCopyAvailablePostScriptNames(): CFArrayRef
proc CTFontManagerCreateFontDescriptorsFromURL(url: CFURLRef): CFArrayRef
{.pop.}

proc cfString(value: string): CFStringRef =
  if value.len == 0:
    return CFStringCreateWithBytes(nil, nil, 0, kCFStringEncodingUTF8, 0'u8)
  CFStringCreateWithBytes(
    nil, unsafeAddr value[0], value.len.CFIndex, kCFStringEncodingUTF8, 0'u8
  )

proc nimString(value: CFStringRef): string =
  if value == nil:
    return
  let capacity =
    CFStringGetMaximumSizeForEncoding(CFStringGetLength(value), kCFStringEncodingUTF8) +
    1
  if capacity <= 1:
    return
  var buffer = newString(capacity.int)
  if CFStringGetCString(
    value, cast[cstring](addr buffer[0]), capacity, kCFStringEncodingUTF8
  ) != 0'u8:
    buffer.setLen(len(cast[cstring](addr buffer[0])))
    result = move(buffer)

proc normalizedName(value: string): string =
  ## Ignore separators commonly interchanged between full and PostScript names.
  result = newStringOfCap(value.len)
  for rune in value.runes:
    if rune notin [Rune(' '), Rune('-'), Rune('_'), Rune('.')]:
      result.add($rune.toLower)

proc isRegularFace(styleName: string, traits: uint32): bool =
  if (traits and (kCTFontTraitBold or kCTFontTraitItalic)) != 0:
    return false
  styleName.normalizedName() in ["regular", "normal", "book", "roman", "plain"]

proc fontMatchesRequest(font: CTFontRef, requested: string): bool =
  let
    requestedName = requested.normalizedName()
    postScript = CTFontCopyPostScriptName(font)
    family = CTFontCopyFamilyName(font)
    full = CTFontCopyFullName(font)
    style = CTFontCopyName(font, kCTFontStyleNameKey)
  defer:
    if postScript != nil:
      CFRelease(postScript)
    if family != nil:
      CFRelease(family)
    if full != nil:
      CFRelease(full)
    if style != nil:
      CFRelease(style)

  if requestedName.len == 0:
    return false
  if requestedName in
      [postScript.nimString().normalizedName(), full.nimString().normalizedName()]:
    return true
  requestedName == family.nimString().normalizedName() and
    isRegularFace(style.nimString(), CTFontGetSymbolicTraits(font))

proc readableFilePath(url: CFURLRef): string =
  var buffer = newSeq[uint8](maxFileSystemPath)
  if CFURLGetFileSystemRepresentation(url, 1'u8, addr buffer[0], buffer.len.CFIndex) ==
      0'u8:
    return
  result = $cast[cstring](addr buffer[0])
  if not result.fileExists:
    result.setLen(0)
    return
  try:
    var file: File
    if not open(file, result, fmRead):
      result.setLen(0)
    else:
      close(file)
  except IOError, OSError:
    result.setLen(0)

proc descriptorPostScriptName(descriptor: CTFontDescriptorRef): string =
  let value =
    cast[CFStringRef](CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute))
  if value != nil:
    result = value.nimString()
    CFRelease(value)

proc collectionFaceCount(path: string): int =
  var file: File
  try:
    if not open(file, path, fmRead):
      return
    defer:
      close(file)
    var header: array[12, uint8]
    if file.readBuffer(addr header[0], header.len) != header.len:
      return
    if header[0] != uint8(ord('t')) or header[1] != uint8(ord('t')) or
        header[2] != uint8(ord('c')) or header[3] != uint8(ord('f')):
      return 1
    result =
      header[8].int shl 24 or header[9].int shl 16 or header[10].int shl 8 or
      header[11].int
  except IOError, OSError:
    discard

proc faceIndex(url: CFURLRef, path, postScriptName: string): int =
  let physicalFaceCount = path.collectionFaceCount()
  if physicalFaceCount == 1:
    return 0
  if physicalFaceCount <= 0:
    return -1
  result = -1
  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url)
  if descriptors == nil:
    return
  defer:
    CFRelease(descriptors)

  if CFArrayGetCount(descriptors).int != physicalFaceCount:
    return
  let selectedName = postScriptName.normalizedName()
  for index in 0 ..< physicalFaceCount:
    let descriptor =
      cast[CTFontDescriptorRef](CFArrayGetValueAtIndex(descriptors, index.CFIndex))
    if descriptor != nil and
        descriptor.descriptorPostScriptName().normalizedName() == selectedName:
      return index

func variationTag(identifier: uint32): string =
  result = newString(4)
  for index in 0 ..< result.len:
    result[index] = char((identifier shr ((result.high - index) * 8)) and 0xff'u32)

proc variations(font: CTFontRef): Option[seq[FontVariation]] =
  let values = CTFontCopyVariation(font)
  if values == nil:
    return some(newSeq[FontVariation]())
  defer:
    CFRelease(values)
  let count = CFDictionaryGetCount(values).int
  if count <= 0:
    return some(newSeq[FontVariation]())
  var
    keys = newSeq[pointer](count)
    coordinates = newSeq[pointer](count)
    parsed: seq[FontVariation]
  CFDictionaryGetKeysAndValues(
    values,
    cast[ptr UncheckedArray[pointer]](addr keys[0]),
    cast[ptr UncheckedArray[pointer]](addr coordinates[0]),
  )
  for index in 0 ..< count:
    var
      identifier: int64
      coordinate: cdouble
    if CFNumberGetValue(
      cast[CFNumberRef](keys[index]), kCFNumberSInt64Type, addr identifier
    ) == 0'u8 or
        CFNumberGetValue(
          cast[CFNumberRef](coordinates[index]), kCFNumberFloat64Type, addr coordinate
        ) == 0'u8:
      return none(seq[FontVariation])
    parsed.add fontVariation(variationTag(cast[uint32](identifier)), coordinate.float32)
  result = some(move parsed)

proc resolvedTypeface(font: CTFontRef): Option[SystemTypeface] =
  let
    postScript = CTFontCopyPostScriptName(font)
    url = cast[CFURLRef](CTFontCopyAttribute(font, kCTFontURLAttribute))
  defer:
    if postScript != nil:
      CFRelease(postScript)
    if url != nil:
      CFRelease(url)
  if postScript == nil or url == nil:
    return

  let
    path = url.readableFilePath()
    index = url.faceIndex(path, postScript.nimString())
    variationCoordinates = font.variations()
  if path.len > 0 and index >= 0 and variationCoordinates.isSome:
    try:
      result = some(initSystemTypeface(path, index, variationCoordinates.get()))
    except ValueError:
      discard

proc typefaceInfo(font: CTFontRef): Option[SystemTypefaceInfo] =
  let file = font.resolvedTypeface()
  if file.isNone:
    return

  let
    family = CTFontCopyFamilyName(font)
    subfamily = CTFontCopyName(font, kCTFontStyleNameKey)
    fullName = CTFontCopyFullName(font)
    postScriptName = CTFontCopyPostScriptName(font)
  defer:
    if family != nil:
      CFRelease(family)
    if subfamily != nil:
      CFRelease(subfamily)
    if fullName != nil:
      CFRelease(fullName)
    if postScriptName != nil:
      CFRelease(postScriptName)
  result = some(
    SystemTypefaceInfo(
      typeface: file.get(),
      family: family.nimString(),
      subfamily: subfamily.nimString(),
      fullName: fullName.nimString(),
      postScriptName: postScriptName.nimString(),
    )
  )

iterator nativeSystemTypefaces*(available: var bool): SystemTypefaceInfo =
  ## Enumerates locally readable Core Text faces in native order.
  block provider:
    let names = CTFontManagerCopyAvailablePostScriptNames()
    if names == nil:
      available = false
      break provider
    available = true
    defer:
      CFRelease(names)

    for index in 0 ..< CFArrayGetCount(names).int:
      let postScriptName =
        cast[CFStringRef](CFArrayGetValueAtIndex(names, index.CFIndex))
      if postScriptName == nil:
        continue
      let font = CTFontCreateWithNameAndOptions(
        postScriptName,
        0.0,
        nil,
        kCTFontOptionsPreventAutoActivation or kCTFontOptionsPreventAutoDownload,
      )
      if font == nil:
        continue
      let info = font.typefaceInfo()
      CFRelease(font)
      if info.isSome:
        yield info.get()

proc findNativeSystemTypeface*(names: openArray[string]): SystemFontProviderResult =
  ## Finds the first exact installed face requested in `names` using Core Text.
  ## A bare family name resolves only to its regular face.
  let availableNames = CTFontManagerCopyAvailablePostScriptNames()
  if availableNames == nil:
    return unavailableSystemFontProvider()
  CFRelease(availableNames)

  result = systemFontProviderMatch(none(SystemTypeface))
  for name in names:
    if name.normalizedName().len == 0:
      continue
    let requestedName = name.cfString()
    if requestedName == nil:
      return unavailableSystemFontProvider()
    let font = CTFontCreateWithNameAndOptions(
      requestedName,
      0.0,
      nil,
      kCTFontOptionsPreventAutoActivation or kCTFontOptionsPreventAutoDownload,
    )
    CFRelease(requestedName)
    if font == nil:
      continue
    if font.fontMatchesRequest(name):
      let match = font.resolvedTypeface()
      if match.isSome:
        CFRelease(font)
        return systemFontProviderMatch(match)
    CFRelease(font)
