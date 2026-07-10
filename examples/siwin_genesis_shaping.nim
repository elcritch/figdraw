when not defined(emscripten):
  import std/os

import std/[math, strutils, times]

import chroma
import chronicles

import figdraw/windowing/siwinshim

import figdraw/commons
import figdraw/extras/systemfonts
import figdraw/fignodes
import figdraw/figrender as glrenderer

logScope:
  scope = "siwin_scripture_shaping"

const
  RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
  DemoWindowTitle = "Siwin Scripture Shaping"
  CarouselHoldSeconds = 7.0'f32
  CarouselSlideSeconds = 1.4'f32
  ExampleDir = currentSourcePath().parentDir
  RepoDir = ExampleDir.parentDir
  UbuntuFontFile = RepoDir / "data" / "Ubuntu.ttf"
  HebrewFontFile = ExampleDir / "fonts" / "NotoSansHebrew-wdth-wght.ttf"
  EnglishSerifFontCandidates = [
    "New York", "Georgia", "Times New Roman", "Palatino", "PT Serif", "IBM Plex Serif",
    "Noto Serif", "DejaVu Serif", "Liberation Serif", "Cambria", "Constantia", "Times",
  ]
  GreekSerifFontCandidates = [
    "New Athena Unicode", "Gentium Plus", "GFS Didot", "GFS Porson", "Noto Serif",
    "Times New Roman", "Palatino", "Georgia", "DejaVu Serif", "Liberation Serif",
    "Cambria", "Times",
  ]

const
  HebrewGenesis319Rows = [
    "בְּזֵעַת אַפֶּיךָ תֹּאכַל לֶחֶם",
    "עַד שׁוּבְךָ אֶל־הָאֲדָמָה",
    "כִּי מִמֶּנָּה לֻקָּחְתָּ",
    "כִּי־עָפָר אַתָּה", "וְאֶל־עָפָר תָּשׁוּב׃",
  ]
  EnglishGenesis319Rows = [
    "In the sweat of thy face shalt thou eat bread,",
    "till thou return unto the ground;", "for out of it wast thou taken:",
    "for dust thou art,", "and unto dust shalt thou return.",
  ]
  GreekJohn316Rows = [
    "Οὕτω γὰρ ἠγάπησεν ὁ Θεὸς", "τὸν κόσμον,",
    "ὥστε τὸν υἱὸν αὐτοῦ",
    "τὸν μονογενῆ ἔδωκεν,", "ἵνα πᾶς",
    "ὁ πιστεύων εἰς αὐτὸν", "μὴ ἀπόληται,",
    "ἀλλ᾽ ἔχῃ ζωὴν", "αἰώνιον.",
  ]

type DemoFonts = object
  title: FigFont
  label: FigFont
  metric: FigFont
  hebrew: FigFont
  greek: FigFont
  english: FigFont

type PanelPose = object
  xOffset: float32
  opacity: float32

proc requireFile(path: string) =
  if not fileExists(path):
    raise newException(IOError, "Missing demo asset: " & path)

func normalizedFontName(name: string): string =
  result = newStringOfCap(name.len)
  for ch in name.toLowerAscii():
    if ch in {'a' .. 'z', '0' .. '9'}:
      result.add(ch)

func isStyledFontName(name: string): bool =
  let normalized = name.normalizedFontName()
  for style in [
    "bold", "italic", "oblique", "semibold", "black", "heavy", "light", "thin",
    "medium", "condensed",
  ]:
    if normalized.contains(style):
      return true

proc findPreferredSystemFont(
    candidates: openArray[string]
): tuple[path: string, family: string] =
  var fonts: seq[tuple[path, stem, normalized: string]]
  for path in systemFontFiles():
    let stem = splitFile(path).name
    fonts.add((path: path, stem: stem, normalized: stem.normalizedFontName()))

  for candidate in candidates:
    let wanted = candidate.normalizedFontName()
    for font in fonts:
      if font.normalized == wanted:
        return (path: font.path, family: candidate)

  for candidate in candidates:
    let wanted = candidate.normalizedFontName()
    for font in fonts:
      if font.normalized.contains(wanted) and not font.stem.isStyledFontName():
        return (path: font.path, family: candidate)

  for candidate in candidates:
    let wanted = candidate.normalizedFontName()
    for font in fonts:
      if font.normalized.contains(wanted) or wanted.contains(font.normalized):
        return (path: font.path, family: candidate)

proc preferredSystemTypefacePath(
    candidates: openArray[string], fallbackPath: string
): string =
  let systemFont = findPreferredSystemFont(candidates)
  result = systemFont.path
  if result.len > 0:
    info "using preferred system typeface", requested = systemFont.family, path = result
  else:
    result = fallbackPath
    info "using bundled fallback typeface", requested = candidates[0], path = result

func uniformCorners(radius: float32): array[DirectionCorners, uint16] =
  for corner in DirectionCorners:
    result[corner] = radius.uint16

func clamp01(v: float32): float32 =
  max(0.0'f32, min(1.0'f32, v))

func faded(color: ColorRGBA, opacity: float32): ColorRGBA =
  rgba(color.r, color.g, color.b, (color.a.float32 * opacity.clamp01()).uint8)

func moved(box: Rect, dx: float32): Rect =
  rect(box.x + dx, box.y, box.w, box.h)

func smoothStep(t: float32): float32 =
  let x = t.clamp01()
  x * x * (3.0'f32 - 2.0'f32 * x)

func carouselTime(t: float32): float32 =
  let
    cycle = (CarouselHoldSeconds + CarouselSlideSeconds) * 2.0'f32
    cycles = floor((t / cycle).float64).float32
  t - cycles * cycle

func carouselPose(t: float32, panelIndex: int, travel: float32): PanelPose =
  let
    segment = CarouselHoldSeconds + CarouselSlideSeconds
    cycleT = carouselTime(t)

  if cycleT < CarouselHoldSeconds:
    if panelIndex == 0:
      result = PanelPose(xOffset: 0.0'f32, opacity: 1.0'f32)
    else:
      result = PanelPose(xOffset: travel, opacity: 0.0'f32)
  elif cycleT < segment:
    let eased = smoothStep((cycleT - CarouselHoldSeconds) / CarouselSlideSeconds)
    if panelIndex == 0:
      result = PanelPose(xOffset: -travel * eased, opacity: 1.0'f32 - eased)
    else:
      result = PanelPose(xOffset: travel * (1.0'f32 - eased), opacity: eased)
  elif cycleT < segment + CarouselHoldSeconds:
    if panelIndex == 1:
      result = PanelPose(xOffset: 0.0'f32, opacity: 1.0'f32)
    else:
      result = PanelPose(xOffset: travel, opacity: 0.0'f32)
  else:
    let eased =
      smoothStep((cycleT - segment - CarouselHoldSeconds) / CarouselSlideSeconds)
    if panelIndex == 1:
      result = PanelPose(xOffset: -travel * eased, opacity: 1.0'f32 - eased)
    else:
      result = PanelPose(xOffset: travel * (1.0'f32 - eased), opacity: eased)

func layoutStats(label: string, glyphCount, lineCount: int): string =
  label & "  glyphs " & $glyphCount & "  lines " & $lineCount

proc initDemoFonts(): DemoFonts =
  requireFile(UbuntuFontFile)
  requireFile(HebrewFontFile)

  let
    ubuntu = loadTypeface(UbuntuFontFile)
    hebrew = loadTypeface(HebrewFontFile)
    englishSerifPath =
      preferredSystemTypefacePath(EnglishSerifFontCandidates, UbuntuFontFile)
    greekSerifPath =
      preferredSystemTypefacePath(GreekSerifFontCandidates, UbuntuFontFile)
    englishSerif =
      if englishSerifPath == UbuntuFontFile:
        ubuntu
      else:
        loadTypeface(englishSerifPath, [UbuntuFontFile])
    greekSerif =
      if greekSerifPath == englishSerifPath:
        englishSerif
      elif greekSerifPath == UbuntuFontFile:
        ubuntu
      else:
        loadTypeface(greekSerifPath, [UbuntuFontFile])
    commonFeatures = @[fontFeature("kern"), fontFeature("liga"), fontFeature("mark")]
    hebrewFeatures =
      @[
        fontFeature("kern"),
        fontFeature("liga"),
        fontFeature("mark"),
        fontFeature("mkmk"),
      ]

  result = DemoFonts(
    title: FigFont(
      typefaceId: ubuntu,
      size: 28.0'f32,
      lineHeight: 34.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    label: FigFont(
      typefaceId: ubuntu,
      size: 15.0'f32,
      lineHeight: 20.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    metric: FigFont(
      typefaceId: ubuntu,
      size: 13.0'f32,
      lineHeight: 18.0'f32,
      fallbackTypefaceIds: @[hebrew],
      features: commonFeatures,
    ),
    hebrew: FigFont(
      typefaceId: hebrew,
      size: 34.0'f32,
      lineHeight: 54.0'f32,
      fallbackTypefaceIds: @[ubuntu],
      features: hebrewFeatures,
      variations: @[fontVariation("wght", 560.0'f32), fontVariation("wdth", 98.0'f32)],
    ),
    greek: FigFont(
      typefaceId: greekSerif,
      size: 30.0'f32,
      lineHeight: 42.0'f32,
      fallbackTypefaceIds: @[englishSerif, ubuntu, hebrew],
      features: commonFeatures,
    ),
    english: FigFont(
      typefaceId: englishSerif,
      size: 22.0'f32,
      lineHeight: 31.0'f32,
      fallbackTypefaceIds: @[ubuntu, hebrew],
      features: commonFeatures,
    ),
  )

proc addRect(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    fill: Fill,
    corners = 0.0'f32,
    stroke = RenderStroke(),
    shadows: array[ShadowCount, RenderShadow] =
      [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()],
): FigIdx {.discardable.} =
  renders.addChild(
    0.ZLevel,
    parent,
    Fig(
      kind: nkRectangle,
      screenBox: box,
      fill: fill,
      corners: uniformCorners(corners),
      stroke: stroke,
      shadows: shadows,
    ),
  )

proc addTextLayout(
    renders: var Renders, parent: FigIdx, box: Rect, layout: GlyphArrangement
) =
  discard renders.addChild(
    0.ZLevel,
    parent,
    Fig(kind: nkText, screenBox: box, fill: clearColor, textLayout: layout),
  )

proc spanLayout(
    box: Rect,
    spans: openArray[(FontStyle, string)],
    hAlign = Left,
    vAlign = Top,
    wrap = true,
): GlyphArrangement =
  typeset(
    rect(0, 0, box.w, box.h),
    spans,
    hAlign = hAlign,
    vAlign = vAlign,
    minContent = false,
    wrap = wrap,
  )

proc textLayout(
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign = Left,
    vAlign = Top,
    wrap = true,
): GlyphArrangement =
  spanLayout(box, [(fs(font, fill), text)], hAlign, vAlign, wrap)

proc addText(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign = Left,
    vAlign = Top,
    wrap = true,
) =
  let layout = textLayout(box, font, text, fill, hAlign, vAlign, wrap)
  renders.addTextLayout(parent, box, layout)

proc addColorSwatches(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    colors: array[3, ColorRGBA],
    opacity: float32,
) =
  let
    gap = 7.0'f32
    swatchW = max(12.0'f32, (box.w - gap * 2.0'f32) / 3.0'f32)
  for i, color in colors:
    discard renders.addRect(
      parent,
      rect(box.x + (swatchW + gap) * i.float32, box.y, swatchW, box.h),
      faded(color, opacity),
      corners = 4.0'f32,
    )

proc addCardFrame(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    colors: array[3, ColorRGBA],
    opacity: float32,
): FigIdx =
  result = renders.addRect(
    root,
    box,
    faded(rgba(255, 255, 255, 255), opacity),
    corners = 8.0'f32,
    stroke = RenderStroke(weight: 1.0'f32, fill: faded(rgba(0, 0, 0, 32), opacity)),
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 20.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 8.0'f32,
        fill: faded(rgba(0, 0, 0, 24), opacity),
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )
  renders.addColorSwatches(
    result,
    rect(box.x + 22.0'f32, box.y + 16.0'f32, box.w - 44.0'f32, 8.0'f32),
    colors,
    opacity,
  )

proc addMetricStrip(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    text: string,
    font: FigFont,
    colors: array[3, ColorRGBA],
    opacity: float32,
) =
  renders.addRect(
    parent,
    box,
    linear(faded(colors[0], opacity), faded(colors[1], opacity), axis = fgaX),
    corners = 5.0'f32,
  )
  renders.addText(
    parent,
    box,
    font,
    text,
    faded(rgba(255, 255, 255, 235), opacity),
    hAlign = Center,
    vAlign = Middle,
    wrap = false,
  )

func textBoxWidth(layout: GlyphArrangement): float32 =
  max(layout.bounding.w, 0.0'f32)

proc measureText(font: FigFont, text: string): float32 =
  if text.len == 0:
    return 0.0'f32

  let layout = textLayout(
    rect(0, 0, 10000.0'f32, max(font.lineHeight, font.size)),
    font,
    text,
    clearColor,
    wrap = false,
  )
  layout.textBoxWidth()

proc maxMeasuredText(font: FigFont, texts: openArray[string]): float32 =
  for text in texts:
    result = max(result, font.measureText(text))

func cardHeaderFont(fonts: DemoFonts, textSize, lineHeight: float32): FigFont =
  FigFont(
    typefaceId: fonts.english.typefaceId,
    size: max(15.0'f32, textSize * 0.64'f32),
    lineHeight: lineHeight,
    fallbackTypefaceIds: fonts.english.fallbackTypefaceIds,
    features: fonts.english.features,
    variations: fonts.english.variations,
  )

proc addCardHeaderText(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    uppercase = false,
) =
  let displayText =
    if uppercase:
      text.toUpperAscii()
    else:
      text
  let layout = textLayout(
    box, font, displayText, fill, hAlign = Left, vAlign = Middle, wrap = false
  )
  renders.addTextLayout(parent, box, layout)

proc addKnuthTextPart(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign: FontHorizontal,
    glyphCount: var int,
) =
  if text.len == 0:
    return

  let layout =
    textLayout(box, font, text, fill, hAlign = hAlign, vAlign = Middle, wrap = false)
  glyphCount += layout.arrangedGlyphs.len
  renders.addTextLayout(parent, box, layout)

proc addKnuthCenteredLine(
    renders: var Renders,
    parent: FigIdx,
    bodyBox: Rect,
    firstY: float32,
    lineH: float32,
    lineIndex: int,
    font: FigFont,
    text: string,
    fill: Fill,
    glyphCount: var int,
    renderedLines: var int,
) =
  let lineBox = rect(bodyBox.x, firstY + lineH * lineIndex.float32, bodyBox.w, lineH)
  renders.addKnuthTextPart(parent, lineBox, font, text, fill, Center, glyphCount)
  inc renderedLines

proc addKnuthAcrosticLine(
    renders: var Renders,
    parent: FigIdx,
    bodyBox: Rect,
    firstY: float32,
    lineH: float32,
    lineIndex: int,
    redX: float32,
    font: FigFont,
    prefix, redLetter, suffix: string,
    blackFill, redFill: Fill,
    glyphCount: var int,
    renderedLines: var int,
) =
  let
    y = firstY + lineH * lineIndex.float32
    redW = max(1.0'f32, font.measureText(redLetter))
    suffixX = redX + redW
    prefixBox = rect(bodyBox.x, y, max(0.0'f32, redX - bodyBox.x), lineH)
    redBox = rect(redX, y, redW, lineH)
    suffixBox = rect(suffixX, y, max(0.0'f32, bodyBox.x + bodyBox.w - suffixX), lineH)

  renders.addKnuthTextPart(
    parent, prefixBox, font, prefix, blackFill, Right, glyphCount
  )
  renders.addKnuthTextPart(parent, redBox, font, redLetter, redFill, Left, glyphCount)
  renders.addKnuthTextPart(parent, suffixBox, font, suffix, blackFill, Left, glyphCount)
  inc renderedLines

proc addKnuthLeftLine(
    renders: var Renders,
    parent: FigIdx,
    bodyBox: Rect,
    firstY: float32,
    lineH: float32,
    lineIndex: int,
    x: float32,
    font: FigFont,
    text: string,
    fill: Fill,
    glyphCount: var int,
    renderedLines: var int,
) =
  let lineBox = rect(
    x,
    firstY + lineH * lineIndex.float32,
    max(0.0'f32, bodyBox.x + bodyBox.w - x),
    lineH,
  )
  renders.addKnuthTextPart(parent, lineBox, font, text, fill, Left, glyphCount)
  inc renderedLines

proc addFixedLineRow(
    renders: var Renders,
    parent: FigIdx,
    bodyBox: Rect,
    firstY: float32,
    lineH: float32,
    lineIndex: int,
    font: FigFont,
    text: string,
    fill: Fill,
    hAlign: FontHorizontal,
    glyphCount: var int,
    renderedLines: var int,
) =
  let lineBox = rect(bodyBox.x, firstY + lineH * lineIndex.float32, bodyBox.w, lineH)
  renders.addKnuthTextPart(parent, lineBox, font, text, fill, hAlign, glyphCount)
  inc renderedLines

proc addKnuthJohnCard(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    fonts: DemoFonts,
    colors: array[3, ColorRGBA],
    opacity: float32,
) =
  if opacity <= 0.01'f32:
    return

  let card = renders.addCardFrame(root, box, colors, opacity)
  let
    pad = 22.0'f32
    contentW = box.w - pad * 2.0'f32
    titleLineH = 24.0'f32
    titleBox = rect(box.x + pad, box.y + 36.0'f32, contentW, titleLineH)
    langBox = rect(box.x + pad, titleBox.y + titleBox.h + 4.0'f32, contentW, titleLineH)
    metricBox = rect(box.x + pad, box.y + box.h - 43.0'f32, contentW, 30.0'f32)
    bodyBox = rect(
      box.x + pad,
      langBox.y + langBox.h + 8.0'f32,
      contentW,
      max(120.0'f32, metricBox.y - langBox.y - langBox.h - 20.0'f32),
    )
    lineCount = 9
    heightLineH = max(17.0'f32, min(36.0'f32, (bodyBox.h - 8.0'f32) / 9.4'f32))
    textSize = max(14.0'f32, min(heightLineH * 0.86'f32, bodyBox.w / 15.0'f32))
    lineH = max(17.0'f32, textSize * 1.18'f32)
    quoteFont = FigFont(
      typefaceId: fonts.english.typefaceId,
      size: textSize,
      lineHeight: lineH,
      fallbackTypefaceIds: fonts.english.fallbackTypefaceIds,
      features: fonts.english.features,
      variations: fonts.english.variations,
    )
    headerFont = cardHeaderFont(fonts, textSize, titleLineH)
    blackFill = faded(rgba(12, 14, 16, 255), opacity)
    redFill = faded(rgba(214, 0, 44, 255), opacity)
    blueFill = faded(rgba(0, 118, 188, 255), opacity)
    languageFill = faded(rgba(74, 84, 94, 235), opacity)
    linesH = lineH * lineCount.float32
    firstY = bodyBox.y + max(0.0'f32, (bodyBox.h - linesH) * 0.42'f32)
    canPrefixW = quoteFont.measureText("can ")
    longestSuffixW = quoteFont.maxMeasuredText(
      [
        "ave his", "nly Child;", "o that all", "eople with faith in him",
        "scape destruction and", "ive a full life,",
      ]
    )
    longestRedW = quoteFont.maxMeasuredText(["G", "O", "S", "P", "E", "L"])
    idealRedX = bodyBox.x + bodyBox.w * 0.34'f32
    minRedX = bodyBox.x + canPrefixW
    maxRedX = bodyBox.x + bodyBox.w - longestRedW - longestSuffixW
    redX = max(minRedX, min(idealRedX, maxRedX))
    finalLineX = max(bodyBox.x, redX - canPrefixW)

  renders.addCardHeaderText(
    card, titleBox, headerFont, "John 3:16", blueFill, uppercase = true
  )
  renders.addCardHeaderText(
    card, langBox, headerFont, "English, after Knuth john316.pdf", languageFill
  )

  var
    glyphCount = 0
    renderedLines = 0

  renders.addKnuthCenteredLine(
    card, bodyBox, firstY, lineH, 0, quoteFont, "Yes, this is how God", blackFill,
    glyphCount, renderedLines,
  )
  renders.addKnuthCenteredLine(
    card, bodyBox, firstY, lineH, 1, quoteFont, "loved the world:", blackFill,
    glyphCount, renderedLines,
  )
  renders.addKnuthAcrosticLine(
    card, bodyBox, firstY, lineH, 2, redX, quoteFont, "He ", "G", "ave his", blackFill,
    redFill, glyphCount, renderedLines,
  )
  renders.addKnuthAcrosticLine(
    card, bodyBox, firstY, lineH, 3, redX, quoteFont, "", "O", "nly Child;", blackFill,
    redFill, glyphCount, renderedLines,
  )
  renders.addKnuthAcrosticLine(
    card, bodyBox, firstY, lineH, 4, redX, quoteFont, "", "S", "o that all", blackFill,
    redFill, glyphCount, renderedLines,
  )
  renders.addKnuthAcrosticLine(
    card, bodyBox, firstY, lineH, 5, redX, quoteFont, "", "P",
    "eople with faith in him", blackFill, redFill, glyphCount, renderedLines,
  )
  renders.addKnuthAcrosticLine(
    card, bodyBox, firstY, lineH, 6, redX, quoteFont, "can ", "E",
    "scape destruction and", blackFill, redFill, glyphCount, renderedLines,
  )
  renders.addKnuthAcrosticLine(
    card, bodyBox, firstY, lineH, 7, redX, quoteFont, "", "L", "ive a full life,",
    blackFill, redFill, glyphCount, renderedLines,
  )
  renders.addKnuthLeftLine(
    card, bodyBox, firstY, lineH, 8, finalLineX, quoteFont, "now and forever.",
    blackFill, glyphCount, renderedLines,
  )

  renders.addMetricStrip(
    card,
    metricBox,
    layoutStats("Knuth-style English", glyphCount, renderedLines),
    fonts.metric,
    colors,
    opacity,
  )

proc addFixedLineQuoteCard(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    reference: string,
    language: string,
    rows: openArray[string],
    font: FigFont,
    fonts: DemoFonts,
    colors: array[3, ColorRGBA],
    opacity: float32,
    hAlign: FontHorizontal = Center,
) =
  if opacity <= 0.01'f32 or rows.len == 0:
    return

  let card = renders.addCardFrame(root, box, colors, opacity)
  let
    pad = 22.0'f32
    contentW = box.w - pad * 2.0'f32
    titleLineH = 24.0'f32
    titleBox = rect(box.x + pad, box.y + 36.0'f32, contentW, titleLineH)
    langBox = rect(box.x + pad, titleBox.y + titleBox.h + 4.0'f32, contentW, titleLineH)
    metricBox = rect(box.x + pad, box.y + box.h - 43.0'f32, contentW, 30.0'f32)
    bodyBox = rect(
      box.x + pad,
      langBox.y + langBox.h + 8.0'f32,
      contentW,
      max(120.0'f32, metricBox.y - langBox.y - langBox.h - 20.0'f32),
    )
    rowCount = rows.len
    heightLineH =
      max(17.0'f32, min(36.0'f32, (bodyBox.h - 8.0'f32) / (rowCount.float32 + 0.4'f32)))
    lineH = max(17.0'f32, heightLineH * 1.01'f32)
    textSize = max(14.0'f32, min(font.size, min(lineH * 0.7'f32, bodyBox.w / 18.0'f32)))
    quoteFont = FigFont(
      typefaceId: font.typefaceId,
      size: textSize,
      lineHeight: lineH,
      fallbackTypefaceIds: font.fallbackTypefaceIds,
      features: font.features,
      variations: font.variations,
    )
    headerFont = cardHeaderFont(fonts, textSize, titleLineH)
    firstY = bodyBox.y + max(0.0'f32, (bodyBox.h - lineH * rowCount.float32) * 0.42'f32)
    textFill = faded(rgba(18, 20, 24, 255), opacity)
    blueFill = faded(rgba(0, 118, 188, 255), opacity)
    languageFill = faded(rgba(74, 84, 94, 235), opacity)

  renders.addCardHeaderText(
    card, titleBox, headerFont, reference, blueFill, uppercase = true
  )
  renders.addCardHeaderText(card, langBox, headerFont, language, languageFill)

  var
    glyphCount = 0
    renderedLines = 0
  for i, row in rows:
    renders.addFixedLineRow(
      card, bodyBox, firstY, lineH, i, quoteFont, row, textFill, hAlign, glyphCount,
      renderedLines,
    )

  renders.addMetricStrip(
    card,
    metricBox,
    layoutStats(language, glyphCount, renderedLines),
    fonts.metric,
    colors,
    opacity,
  )

func cardPair(page: Rect): tuple[first: Rect, second: Rect] =
  let gap = 20.0'f32
  if page.w >= 760.0'f32:
    let cardW = (page.w - gap) * 0.5'f32
    result = (
      first: rect(page.x, page.y, cardW, page.h),
      second: rect(page.x + cardW + gap, page.y, cardW, page.h),
    )
  else:
    let cardH = (page.h - gap) * 0.5'f32
    result = (
      first: rect(page.x, page.y, page.w, cardH),
      second: rect(page.x, page.y + cardH + gap, page.w, cardH),
    )

proc addGenesisPage(
    renders: var Renders, root: FigIdx, page: Rect, fonts: DemoFonts, pose: PanelPose
) =
  let
    cards = cardPair(page.moved(pose.xOffset))
    hebrewColors: array[3, ColorRGBA] =
      [rgba(21, 135, 115, 245), rgba(45, 92, 145, 245), rgba(214, 143, 42, 245)]
    englishColors: array[3, ColorRGBA] =
      [rgba(214, 143, 42, 245), rgba(156, 86, 52, 245), rgba(45, 92, 145, 245)]
  renders.addFixedLineQuoteCard(
    root, cards.first, "Genesis 3:19", "Hebrew", HebrewGenesis319Rows, fonts.hebrew,
    fonts, hebrewColors, pose.opacity,
  )
  renders.addFixedLineQuoteCard(
    root, cards.second, "Genesis 3:19", "English KJV", EnglishGenesis319Rows,
    fonts.english, fonts, englishColors, pose.opacity,
  )

proc addJohnPage(
    renders: var Renders, root: FigIdx, page: Rect, fonts: DemoFonts, pose: PanelPose
) =
  let
    cards = cardPair(page.moved(pose.xOffset))
    greekColors: array[3, ColorRGBA] =
      [rgba(114, 68, 160, 245), rgba(58, 112, 188, 245), rgba(166, 62, 86, 245)]
    englishColors: array[3, ColorRGBA] =
      [rgba(214, 0, 44, 245), rgba(12, 14, 16, 245), rgba(0, 118, 188, 245)]
  renders.addFixedLineQuoteCard(
    root, cards.first, "John 3:16", "Greek", GreekJohn316Rows, fonts.greek, fonts,
    greekColors, pose.opacity,
  )
  renders.addKnuthJohnCard(root, cards.second, fonts, englishColors, pose.opacity)

proc addGenesisPanel(
    renders: var Renders, root: FigIdx, box: Rect, fonts: DemoFonts, pose: PanelPose
) =
  renders.addGenesisPage(root, box, fonts, pose)

proc addJohnPanel(
    renders: var Renders, root: FigIdx, box: Rect, fonts: DemoFonts, pose: PanelPose
) =
  renders.addJohnPage(root, box, fonts, pose)

proc makeRenderTree*(w, h: float32, fonts: DemoFonts, timeSec = 0.0'f32): Renders =
  result = Renders()

  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, w, h),
      fill: linear(rgba(238, 241, 246, 255), rgba(218, 225, 234, 255), axis = fgaY),
    ),
  )

  let
    pad = 28.0'f32
    titleHeight = 70.0'f32
    usableW = max(360.0'f32, w - pad * 2.0'f32)
    stage = rect(
      pad, pad + titleHeight, usableW, max(340.0'f32, h - pad * 2.0'f32 - titleHeight)
    )
    panelW = min(980.0'f32, max(460.0'f32, usableW * 0.96'f32))
    panelH = min(620.0'f32, max(340.0'f32, stage.h))
    panel = rect(
      stage.x + (stage.w - panelW) * 0.5'f32,
      stage.y + (stage.h - panelH) * 0.5'f32,
      panelW,
      panelH,
    )
    travel = usableW + panelW * 0.5'f32
    genesisPose = carouselPose(timeSec, 0, travel)
    johnPose = carouselPose(timeSec, 1, travel)

  result.addText(
    root,
    rect(pad, pad, usableW, 34.0'f32),
    fonts.title,
    "Scripture Text Shaping",
    linear(rgba(30, 42, 58, 255), rgba(45, 92, 145, 255), axis = fgaX),
    wrap = false,
  )
  result.addText(
    root,
    rect(pad, pad + 34.0'f32, usableW, 24.0'f32),
    fonts.metric,
    "backend: " & figdrawTextBackend,
    rgba(74, 84, 94, 255),
    wrap = false,
  )

  if genesisPose.opacity <= johnPose.opacity:
    result.addGenesisPanel(root, panel, fonts, genesisPose)
    result.addJohnPanel(root, panel, fonts, johnPose)
  else:
    result.addJohnPanel(root, panel, fonts, johnPose)
    result.addGenesisPanel(root, panel, fonts, genesisPose)

when isMainModule:
  var appRunning = true

  let
    title = siwinWindowTitle(DemoWindowTitle)
    size = ivec2(1040, 820)
    fonts = initDemoFonts()

  when UseVulkanBackend:
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = size, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = size, fullscreen = false, title = title)
    let renderer =
      glrenderer.newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()
  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, DemoWindowTitle)

  info "Scripture shaping demo startup",
    textBackend = figdrawTextBackend,
    windowW = appWindow.backingSize().x,
    windowH = appWindow.backingSize().y,
    scale = appWindow.contentScale()

  let animStart = epochTime()
  var renders = makeRenderTree(0.0'f32, 0.0'f32, fonts, 0.0'f32)

  proc redraw() =
    renderer.beginFrame()
    let sz = appWindow.logicalSize()
    renders = makeRenderTree(sz.x, sz.y, fonts, (epochTime() - animStart).float32)
    renderer.renderFrame(renders, sz)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      appRunning = false,
    onResize: proc(e: ResizeEvent) =
      appWindow.refreshUiScale(useAutoScale)
      redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        close(e.window)
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  appWindow.firstStep()
  appWindow.refreshUiScale(useAutoScale)

  try:
    var frames = 0
    while appRunning and appWindow.opened:
      appWindow.redraw()
      appWindow.step()
      inc frames
      if RunOnce and frames >= 1:
        appRunning = false
      else:
        when not defined(emscripten):
          sleep(16)
  finally:
    when not defined(emscripten):
      appWindow.close()
