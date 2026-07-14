import std/[algorithm, os, strutils, tables, unicode]

type
  ## A localized entry from the OpenType `name` table.
  TypefaceLocalizedName* = object
    nameId*: uint16
    platformId*: uint16
    encodingId*: uint16
    languageId*: uint16
    languageTag*: string ## BCP 47 language tag, when the font identifies one.
    text*: string

  ## One design axis from an OpenType variable font.
  TypefaceVariationAxis* = object
    tag*: string
    name*: string
    minValue*: float32
    defaultValue*: float32
    maxValue*: float32
    hidden*: bool

  ## Backend-neutral metadata for one registered typeface face.
  ##
  ## `layoutScripts` and `layoutLanguages` contain OpenType shaping tags from
  ## GSUB and GPOS. They describe shaping support rather than localized name
  ## languages.
  TypefaceInfo* = object
    family*: string
    subfamily*: string
    fullName*: string
    postScriptName*: string
    faceIndex*: int
    weightClass*: uint16
    widthClass*: uint16
    bold*: bool
    italic*: bool
    oblique*: bool
    regular*: bool
    monospace*: bool
    unicodeRanges*: array[4, uint32]
    codePageRanges*: array[2, uint32]
    localizedNames*: seq[TypefaceLocalizedName]
    variationAxes*: seq[TypefaceVariationAxis]
    layoutScripts*: seq[string]
    layoutLanguages*: seq[string]

  TypefaceTable = object
    offset: int
    length: int

proc requireBytes(data: string, offset, length: int) =
  if offset < 0 or length < 0 or offset > data.len - length:
    raise newException(ValueError, "font metadata extends past the source data")

proc uint16Be(data: string, offset: int): uint16 =
  data.requireBytes(offset, 2)
  uint16(data[offset].ord shl 8 or data[offset + 1].ord)

proc uint32Be(data: string, offset: int): uint32 =
  data.requireBytes(offset, 4)
  uint32(data[offset].ord) shl 24 or uint32(data[offset + 1].ord) shl 16 or
    uint32(data[offset + 2].ord) shl 8 or uint32(data[offset + 3].ord)

proc int32Be(data: string, offset: int): int32 =
  cast[int32](data.uint32Be(offset))

proc fixed16Dot16(data: string, offset: int): float32 =
  data.int32Be(offset).float32 / 65536.0'f32

proc tagAt(data: string, offset: int): string =
  data.requireBytes(offset, 4)
  data[offset ..< offset + 4]

proc sfntOffset(data: string, faceIndex: int): int =
  data.requireBytes(0, 4)
  if data[0 ..< 4] != "ttcf":
    return 0
  data.requireBytes(0, 12)
  let faceCount = data.uint32Be(8).int
  if faceIndex notin 0 ..< faceCount:
    raise newException(ValueError, "font collection face index is out of bounds")
  data.uint32Be(12 + faceIndex * 4).int

proc readTypefaceTables(data: string, faceIndex: int): Table[string, TypefaceTable] =
  let offset = data.sfntOffset(faceIndex)
  data.requireBytes(offset, 12)
  let tableCount = data.uint16Be(offset + 4).int
  data.requireBytes(offset + 12, tableCount * 16)
  for index in 0 ..< tableCount:
    let
      recordOffset = offset + 12 + index * 16
      tag = data.tagAt(recordOffset)
      tableOffset = data.uint32Be(recordOffset + 8).int
      tableLength = data.uint32Be(recordOffset + 12).int
    data.requireBytes(tableOffset, tableLength)
    result[tag] = TypefaceTable(offset: tableOffset, length: tableLength)

proc utf16Be(data: string, offset, length: int): string =
  data.requireBytes(offset, length)
  var index = offset
  let limit = offset + length - length mod 2
  while index < limit:
    let first = data.uint16Be(index)
    index += 2
    var codepoint = first.uint32
    if first in 0xD800'u16 .. 0xDBFF'u16 and index < limit:
      let second = data.uint16Be(index)
      if second in 0xDC00'u16 .. 0xDFFF'u16:
        index += 2
        codepoint =
          0x10000'u32 + (first.uint32 - 0xD800'u32) * 0x400'u32 + second.uint32 -
          0xDC00'u32
    if codepoint != 0:
      result.add $Rune(codepoint.int32)

proc singleByteName(data: string, offset, length: int): string =
  data.requireBytes(offset, length)
  for index in offset ..< offset + length:
    let value = data[index].ord
    if value != 0:
      result.add $Rune(value.int32)

func windowsLanguageTag(languageId: uint16): string =
  case languageId
  of 0x0401'u16: "ar-SA"
  of 0x0404'u16: "zh-TW"
  of 0x0407'u16: "de-DE"
  of 0x0409'u16: "en-US"
  of 0x040A'u16: "es-ES"
  of 0x040C'u16: "fr-FR"
  of 0x040D'u16: "he-IL"
  of 0x0410'u16: "it-IT"
  of 0x0411'u16: "ja-JP"
  of 0x0412'u16: "ko-KR"
  of 0x0419'u16: "ru-RU"
  of 0x041E'u16: "th-TH"
  of 0x0429'u16: "fa-IR"
  of 0x0439'u16: "hi-IN"
  of 0x0804'u16: "zh-CN"
  else: ""

func localizedLanguageTag(
    platformId, languageId: uint16, languageTags: openArray[string]
): string =
  if languageId >= 0x8000'u16:
    let index = languageId.int - 0x8000
    if index in 0 ..< languageTags.len:
      return languageTags[index]
  if platformId == 3:
    return languageId.windowsLanguageTag()
  ""

func isUnicodeNameEncoding(platformId, encodingId: uint16): bool =
  platformId == 0 or platformId == 3 and encodingId in {0'u16, 1'u16, 10'u16}

proc readNameText(
    data: string, offset, length: int, platformId, encodingId: uint16
): string =
  if platformId.isUnicodeNameEncoding(encodingId):
    data.utf16Be(offset, length)
  else:
    data.singleByteName(offset, length)

proc readLanguageTags(
    data: string, nameTable: TypefaceTable, recordCount, stringOffset: int
): seq[string] =
  let languageCountOffset = nameTable.offset + 6 + recordCount * 12
  if languageCountOffset + 2 > nameTable.offset + nameTable.length:
    return
  let languageCount = data.uint16Be(languageCountOffset).int
  data.requireBytes(languageCountOffset + 2, languageCount * 4)
  for index in 0 ..< languageCount:
    let
      recordOffset = languageCountOffset + 2 + index * 4
      length = data.uint16Be(recordOffset).int
      offset = data.uint16Be(recordOffset + 2).int
    result.add data.utf16Be(nameTable.offset + stringOffset + offset, length)

proc readLocalizedNames(
    data: string, tables: Table[string, TypefaceTable]
): seq[TypefaceLocalizedName] =
  if "name" notin tables:
    return
  let table = tables["name"]
  data.requireBytes(table.offset, 6)
  let
    format = data.uint16Be(table.offset)
    recordCount = data.uint16Be(table.offset + 2).int
    stringOffset = data.uint16Be(table.offset + 4).int
    languageTags =
      if format == 1:
        data.readLanguageTags(table, recordCount, stringOffset)
      else:
        @[]
  data.requireBytes(table.offset + 6, recordCount * 12)
  for index in 0 ..< recordCount:
    let
      recordOffset = table.offset + 6 + index * 12
      platformId = data.uint16Be(recordOffset)
      encodingId = data.uint16Be(recordOffset + 2)
      languageId = data.uint16Be(recordOffset + 4)
      nameId = data.uint16Be(recordOffset + 6)
      length = data.uint16Be(recordOffset + 8).int
      offset = data.uint16Be(recordOffset + 10).int
      text = data.readNameText(
        table.offset + stringOffset + offset, length, platformId, encodingId
      )
    if text.len > 0:
      result.add TypefaceLocalizedName(
        nameId: nameId,
        platformId: platformId,
        encodingId: encodingId,
        languageId: languageId,
        languageTag: localizedLanguageTag(platformId, languageId, languageTags),
        text: text,
      )

func preferredName(
    names: openArray[TypefaceLocalizedName], nameIds: openArray[uint16]
): string =
  for nameId in nameIds:
    for name in names:
      if name.nameId == nameId and name.languageTag.startsWith("en"):
        return name.text
    for name in names:
      if name.nameId == nameId and name.platformId in {0'u16, 3'u16}:
        return name.text
    for name in names:
      if name.nameId == nameId:
        return name.text

proc addUnique(values: var seq[string], value: string) =
  if value.len > 0 and value notin values:
    values.add value

proc readLayoutTags(
    data: string, table: TypefaceTable, scripts, languages: var seq[string]
) =
  data.requireBytes(table.offset, 10)
  let scriptListOffset = data.uint16Be(table.offset + 4).int
  if scriptListOffset == 0:
    return
  let scriptList = table.offset + scriptListOffset
  let scriptCount = data.uint16Be(scriptList).int
  data.requireBytes(scriptList + 2, scriptCount * 6)
  for scriptIndex in 0 ..< scriptCount:
    let
      scriptRecord = scriptList + 2 + scriptIndex * 6
      scriptTag = data.tagAt(scriptRecord).strip()
      scriptOffset = data.uint16Be(scriptRecord + 4).int
      scriptTable = scriptList + scriptOffset
    scripts.addUnique(scriptTag)
    data.requireBytes(scriptTable, 4)
    let languageCount = data.uint16Be(scriptTable + 2).int
    data.requireBytes(scriptTable + 4, languageCount * 6)
    for languageIndex in 0 ..< languageCount:
      let languageRecord = scriptTable + 4 + languageIndex * 6
      languages.addUnique(data.tagAt(languageRecord).strip())

proc readVariationAxes(
    data: string,
    tables: Table[string, TypefaceTable],
    names: openArray[TypefaceLocalizedName],
): seq[TypefaceVariationAxis] =
  if "fvar" notin tables:
    return
  let table = tables["fvar"]
  data.requireBytes(table.offset, 16)
  let
    axesOffset = data.uint16Be(table.offset + 4).int
    axisCount = data.uint16Be(table.offset + 8).int
    axisSize = data.uint16Be(table.offset + 10).int
  if axisSize < 20:
    raise newException(ValueError, "font variation axis record is too short")
  data.requireBytes(table.offset + axesOffset, axisCount * axisSize)
  for index in 0 ..< axisCount:
    let
      axisOffset = table.offset + axesOffset + index * axisSize
      nameId = data.uint16Be(axisOffset + 18)
    result.add TypefaceVariationAxis(
      tag: data.tagAt(axisOffset),
      name: names.preferredName([nameId]),
      minValue: data.fixed16Dot16(axisOffset + 4),
      defaultValue: data.fixed16Dot16(axisOffset + 8),
      maxValue: data.fixed16Dot16(axisOffset + 12),
      hidden: (data.uint16Be(axisOffset + 16) and 1) != 0,
    )

proc applyStyleInfo(
    result: var TypefaceInfo, data: string, tables: Table[string, TypefaceTable]
) =
  if "OS/2" in tables:
    let table = tables["OS/2"]
    data.requireBytes(table.offset, min(table.length, 78))
    result.weightClass = data.uint16Be(table.offset + 4)
    result.widthClass = data.uint16Be(table.offset + 6)
    if table.length >= 62:
      for index in 0 .. 3:
        result.unicodeRanges[index] = data.uint32Be(table.offset + 42 + index * 4)
    if table.length >= 64:
      let selection = data.uint16Be(table.offset + 62)
      result.italic = (selection and (1'u16 shl 0)) != 0
      result.bold = (selection and (1'u16 shl 5)) != 0
      result.regular = (selection and (1'u16 shl 6)) != 0
      result.oblique = (selection and (1'u16 shl 9)) != 0
    if table.length >= 86:
      result.codePageRanges[0] = data.uint32Be(table.offset + 78)
      result.codePageRanges[1] = data.uint32Be(table.offset + 82)
  if "head" in tables and tables["head"].length >= 46:
    let style = data.uint16Be(tables["head"].offset + 44)
    result.bold = result.bold or (style and 1) != 0
    result.italic = result.italic or (style and 2) != 0
  if "post" in tables and tables["post"].length >= 16:
    result.monospace = data.uint32Be(tables["post"].offset + 12) != 0

proc fallbackFamily(sourceName: string): string =
  let fileName = sourceName.extractFilename()
  result = (if fileName.len > 0: fileName else: sourceName).splitFile().name

proc parseTypefaceInfo*(
    sourceName, data: string, faceIndex = 0, fallbackFullName = ""
): TypefaceInfo =
  result.faceIndex = faceIndex
  result.family = sourceName.fallbackFamily()
  result.fullName = fallbackFullName
  if data.len == 0:
    return
  try:
    let tables = data.readTypefaceTables(faceIndex)
    result.localizedNames = data.readLocalizedNames(tables)
    let
      family = result.localizedNames.preferredName([16'u16, 1'u16])
      subfamily = result.localizedNames.preferredName([17'u16, 2'u16])
      fullName = result.localizedNames.preferredName([4'u16])
      postScriptName = result.localizedNames.preferredName([6'u16])
    if family.len > 0:
      result.family = family
    result.subfamily = subfamily
    if fullName.len > 0:
      result.fullName = fullName
    elif result.fullName.len == 0:
      result.fullName = result.family
      if subfamily.len > 0 and subfamily.toLowerAscii() notin ["regular", "normal"]:
        result.fullName.add " " & subfamily
    result.postScriptName = postScriptName
    result.applyStyleInfo(data, tables)
    result.variationAxes = data.readVariationAxes(tables, result.localizedNames)
    for tag in ["GSUB", "GPOS"]:
      if tag in tables:
        data.readLayoutTags(tables[tag], result.layoutScripts, result.layoutLanguages)
    result.layoutScripts.sort()
    result.layoutLanguages.sort()
  except ValueError:
    discard

proc copyTypefaceInfo*(info: TypefaceInfo): TypefaceInfo =
  result = info
  result.localizedNames = newSeqOfCap[TypefaceLocalizedName](info.localizedNames.len)
  for name in info.localizedNames:
    result.localizedNames.add name
  result.variationAxes = newSeqOfCap[TypefaceVariationAxis](info.variationAxes.len)
  for axis in info.variationAxes:
    result.variationAxes.add axis
  result.layoutScripts = newSeqOfCap[string](info.layoutScripts.len)
  for script in info.layoutScripts:
    result.layoutScripts.add script
  result.layoutLanguages = newSeqOfCap[string](info.layoutLanguages.len)
  for language in info.layoutLanguages:
    result.layoutLanguages.add language
