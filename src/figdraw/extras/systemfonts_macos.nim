## Native installed-font lookup for macOS.
##
## Core Text may substitute a fallback when asked to create an unknown font.
## Every result is therefore checked against the requested family, full, or
## PostScript name before its file URL is accepted.

import std/[options, os, unicode]

import ./systemfonttypes

{.passL: "-framework CoreFoundation".}
{.passL: "-framework CoreText".}

type
  CFIndex = clong
  CFStringEncoding = uint32
  CFStringRef = pointer
  CFURLRef = pointer
  CFArrayRef = pointer
  CTFontRef = pointer
  CTFontDescriptorRef = pointer
  CTFontOptions = uint32

const
  kCFStringEncodingUTF8 = 0x08000100'u32
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

proc faceIndex(url: CFURLRef, postScriptName: string): int =
  result = -1
  let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url)
  if descriptors == nil:
    return
  defer:
    CFRelease(descriptors)

  let selectedName = postScriptName.normalizedName()
  for index in 0 ..< CFArrayGetCount(descriptors).int:
    let descriptor =
      cast[CTFontDescriptorRef](CFArrayGetValueAtIndex(descriptors, index.CFIndex))
    if descriptor != nil and
        descriptor.descriptorPostScriptName().normalizedName() == selectedName:
      return index

proc resolvedTypeface(font: CTFontRef): Option[SystemTypefaceFile] =
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
    index = url.faceIndex(postScript.nimString())
  if path.len > 0 and index >= 0:
    result = some(SystemTypefaceFile(path: path, faceIndex: index))

proc findNativeSystemTypefaceFile*(names: openArray[string]): SystemFontProviderResult =
  ## Finds the first exact installed face requested in `names` using Core Text.
  ## A bare family name resolves only to its regular face.
  let availableNames = CTFontManagerCopyAvailablePostScriptNames()
  if availableNames == nil:
    return unavailableSystemFontProvider()
  CFRelease(availableNames)

  result = systemFontProviderMatch(none(SystemTypefaceFile))
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
