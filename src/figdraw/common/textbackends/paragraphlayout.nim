## Backend-neutral paragraph layout over shaped glyphs: line breaking with
## per-line measures, hyphenation, justification, spacing, and alignment.
##
## Backends shape each paragraph onto one baseline, then describe paragraphs
## as visual glyph ranges. Layout keeps glyph geometry arrays in sync and only
## rebuilds spans and display runes when it inserts hyphen glyphs.

import std/[algorithm, math, tables, unicode]

import pkg/vmath

import threading/smartptrs

import ../fonttypes
import ../hyphenation
import ./common

type
  LayoutParagraph* = object
    glyphs*: Slice[int] ## Visual glyph range of one source paragraph; may be empty.
    style*: ParagraphStyle
    language*: string ## BCP 47 language used for hyphenation.
    rightToLeft*: bool ## Base direction of the paragraph.

  HyphenGlyph* = object
    found*: bool
    glyphFont*: GlyphFont
    glyphId*: FontGlyphId
    advance*: float32
    imageOffset*: Vec2

  HyphenResolver* = proc(fontId: FontId): HyphenGlyph {.closure.}
    ## Resolves a visible hyphen glyph in the font of the preceding glyph.

  ParagraphLine* = object
    paragraph*: int ## Index into the laid-out paragraphs.
    first*: bool ## Logical first line of its paragraph.
    last*: bool ## Logical last line of its paragraph.
    rtl*: bool ## The paragraph runs right to left.

  HyphenEdit = enum
    heNone
    heSoftHyphen ## Show the soft hyphen ending the line.
    heInsert ## Insert a hyphen after the line's last glyph.

  BrokenLine = object
    glyphs: Slice[int]
    edit: HyphenEdit

  GlyphFlag = enum
    gfSpace ## Whitespace that hangs at line ends and stretches when justified.
    gfSoftHyphen
    gfSafe ## Shaping-safe cluster boundary after this glyph.
    gfCluster ## Cluster boundary after this glyph, even if shaping-unsafe.
    gfPreferred ## Preferred break opportunity after this glyph.
    gfExplicitHyphen ## Break follows a visible hyphen character.

  HyphenPoint = tuple[index: int, edit: HyphenEdit]

  PatternLookup = object
    found: bool
    patterns: ConstPtr[HyphenationPatterns]

  GlyphRecord = object
    ## One glyph with the per-glyph data that spans and runes otherwise hold.
    glyph: ArrangedGlyph
    selection: Rect
    font: GlyphFont
    color: Fill
    covered: bool
    visualKey: float64 ## Original visual position; orders a line for display.

  LayoutContext = object
    flags: seq[set[GlyphFlag]]
    widths: seq[float32]
    hyphens: Table[FontId, HyphenGlyph]
    patterns: Table[string, PatternLookup] ## Resolved once per language.
    wordPoints: Table[string, seq[int]] ## Hyphenation points by language and word.
    resolver: HyphenResolver
    boxWidth: float32
    wrap: bool

const
  SoftHyphen = Rune(0x00AD)
  JustifyStretch = 0.5'f32
    ## Fraction of a space's width it may grow in optimal breaking.
  JustifyShrink = 1.0'f32 / 3.0'f32 ## Fraction of a space's width it may shrink.
  LinePenalty = 10.0
  HyphenPenalty = 50.0
  DoubleHyphenDemerits = 3000.0
  AdjacentFitnessDemerits = 10000.0

func isSpaceRune*(rune: Rune): bool {.inline.} =
  ## `unicode.isWhiteSpace` with an ASCII fast path; its table search
  ## dominates per-glyph classification otherwise.
  if rune.int < 0x80:
    rune.int in {0x09 .. 0x0d, 0x20}
  else:
    rune.isWhiteSpace

func isCjkLineBreakRune*(rune: Rune): bool =
  let cp = rune.uint32
  cp in 0x1100'u32 .. 0x11ff'u32 or cp in 0x2e80'u32 .. 0x30ff'u32 or
    cp in 0x3400'u32 .. 0x4dbf'u32 or cp in 0x4e00'u32 .. 0x9fff'u32 or
    cp in 0xac00'u32 .. 0xd7af'u32 or cp in 0xf900'u32 .. 0xfaff'u32 or
    cp in 0xff65'u32 .. 0xff9f'u32

func isHyphenRune(rune: Rune): bool =
  case rune.uint32
  of 0x002d'u32,
      0x058a'u32,
      0x05be'u32,
      0x1400'u32,
      0x1806'u32,
      0x2010'u32 .. 0x2015'u32,
      0x2e17'u32,
      0x2e1a'u32,
      0xfe58'u32,
      0xfe63'u32,
      0xff0d'u32:
    true
  else:
    false

func canBreakAfterRune*(rune: Rune): bool =
  ## Break opportunities after spaces, hyphens, dashes, and slashes.
  ## Soft hyphens are handled separately because breaking shows a hyphen.
  if rune.int < 0x80:
    return rune.int in {0x09 .. 0x0d, 0x20, 0x2d, 0x2f}
  if rune.isWhiteSpace or rune.isHyphenRune:
    return true
  case rune.uint32
  of 0x002f'u32,
      0x200b'u32,
      0x2053'u32,
      0x207b'u32,
      0x208b'u32,
      0x2212'u32,
      0x301c'u32,
      0x3030'u32,
      0x30a0'u32,
      0xfe31'u32 .. 0xfe32'u32:
    true
  else:
    false

proc glyphWrapWidth*(glyph: ArrangedGlyph): float32 {.inline.} =
  max(glyph.rect.w, abs(glyph.advance.x))

func hasLayoutStyle*(paragraphs: openArray[LayoutParagraph]): bool =
  for paragraph in paragraphs:
    if not paragraph.style.isDefault:
      return true

proc firstSourceRune(arrangement: GlyphArrangement, glyph: ArrangedGlyph): Rune =
  let source = arrangement.sourceRunes
  if source.isNil or glyph.source.byteEnd <= glyph.source.byteStart or
      glyph.source.byteStart >= source.byteLength:
    return Rune(0)
  source.bytes.runeAt(glyph.source.byteStart)

proc lastSourceRune(arrangement: GlyphArrangement, glyph: ArrangedGlyph): Rune =
  let source = arrangement.sourceRunes
  if source.isNil or glyph.source.byteEnd <= glyph.source.byteStart or
      glyph.source.byteEnd > source.byteLength:
    return Rune(0)
  source.bytes.lastRune(glyph.source.byteEnd - 1)[0]

proc decompose(arrangement: GlyphArrangement): seq[GlyphRecord] =
  result = newSeq[GlyphRecord](arrangement.arrangedGlyphs.len)
  for index, glyph in arrangement.arrangedGlyphs:
    result[index].glyph = glyph
    result[index].selection = arrangement.selectionRects[index]
    result[index].visualKey = index.float64
  for spanIndex, span in arrangement.spans:
    for glyphIndex in span:
      if glyphIndex in 0 ..< result.len:
        result[glyphIndex].font = arrangement.fonts[spanIndex]
        result[glyphIndex].color = arrangement.spanColors[spanIndex]
        result[glyphIndex].covered = true

proc recompose(arrangement: var GlyphArrangement, records: openArray[GlyphRecord]) =
  ## Rebuilds glyph arrays, merged spans, and display runes from records.
  arrangement.arrangedGlyphs.setLen(records.len)
  arrangement.positions.setLen(records.len)
  arrangement.selectionRects.setLen(records.len)
  arrangement.spans.setLen(0)
  arrangement.fonts.setLen(0)
  arrangement.spanColors.setLen(0)
  var display = newStringOfCap(records.len)
  for index, record in records:
    arrangement.arrangedGlyphs[index] = record.glyph
    arrangement.positions[index] = record.glyph.pos
    arrangement.selectionRects[index] = record.selection
    display.add record.glyph.rune
    if not record.covered:
      continue
    if arrangement.spans.len > 0 and arrangement.spans[^1].b == index - 1 and
        arrangement.fonts[^1] == record.font and
        arrangement.spanColors[^1] == record.color:
      arrangement.spans[^1].b = index
    else:
      arrangement.spans.add index .. index
      arrangement.fonts.add record.font
      arrangement.spanColors.add record.color
  arrangement.runes = initArrangementRunes(display)

proc runsInLogicalOrder(arrangement: GlyphArrangement, range: Slice[int]): bool =
  for index in range.a ..< range.b:
    if arrangement.arrangedGlyphs[index + 1].source.runeStart <
        arrangement.arrangedGlyphs[index].source.runeStart:
      return false
  true

proc orderLogically(
    arrangement: var GlyphArrangement,
    paragraphs: openArray[LayoutParagraph],
    breakAfter: openArray[bool],
    records: var seq[GlyphRecord],
    reordered: var seq[bool],
): seq[bool] =
  ## Puts the glyphs of bidirectional paragraphs in source order so lines
  ## break from the paragraph's logical start; display order is restored per
  ## line afterward. Returns shaping-safe flags for the new order.
  result = @breakAfter
  reordered = newSeq[bool](paragraphs.len)
  var any = false
  for paragraphIndex, paragraph in paragraphs:
    if paragraph.glyphs.a < paragraph.glyphs.b and
        not arrangement.runsInLogicalOrder(paragraph.glyphs):
      reordered[paragraphIndex] = true
      any = true
  if not any:
    return
  records = arrangement.decompose()
  if result.len < records.len:
    let known = result.len
    result.setLen(records.len)
    for index in known ..< records.len:
      result[index] = true
  let visualSafe = result
  for paragraphIndex, paragraph in paragraphs:
    if not reordered[paragraphIndex]:
      continue
    let range = paragraph.glyphs
    var slice = records[range.a .. range.b]
    slice.sort(
      proc(a, b: GlyphRecord): int =
        result = cmp(a.glyph.source.runeStart, b.glyph.source.runeStart)
        if result == 0:
          result = cmp(a.visualKey, b.visualKey)
    )
    for offset, record in slice:
      records[range.a + offset] = record
    # A logical neighbor pair is shaping-safe where it is visually adjacent
    # and HarfBuzz marked that visual boundary safe.
    for index in range.a ..< range.b:
      let
        here = int(records[index].visualKey)
        next = int(records[index + 1].visualKey)
      result[index] =
        if abs(here - next) == 1:
          visualSafe[min(here, next)]
        else:
          true
    result[range.b] = true
  arrangement.recompose(records)

proc classifyGlyphs(
    ctx: var LayoutContext,
    arrangement: var GlyphArrangement,
    paragraphs: openArray[LayoutParagraph],
    breakAfter: openArray[bool],
) =
  ## One linear pass over the source bytes; no rune-index lookups.
  let count = arrangement.arrangedGlyphs.len
  ctx.flags = newSeq[set[GlyphFlag]](count)
  ctx.widths = newSeq[float32](count)
  for paragraph in paragraphs:
    let range = paragraph.glyphs
    if range.a > range.b:
      continue
    var nextFirst = arrangement.firstSourceRune(arrangement.arrangedGlyphs[range.a])
    for index in range:
      let
        glyph = arrangement.arrangedGlyphs[index]
        first = nextFirst
        last = arrangement.lastSourceRune(glyph)
        hasNext = index < range.b
      nextFirst =
        if hasNext:
          arrangement.firstSourceRune(arrangement.arrangedGlyphs[index + 1])
        else:
          Rune(0)
      var flags: set[GlyphFlag]
      if first == SoftHyphen and glyph.source.runeEnd - glyph.source.runeStart == 1:
        flags.incl gfSoftHyphen
        # Unbroken soft hyphens are invisible and take no space.
        arrangement.arrangedGlyphs[index].isWhitespace = true
        arrangement.arrangedGlyphs[index].advance.x = 0
        arrangement.arrangedGlyphs[index].rect.w = 0
        arrangement.selectionRects[index].w = 0
      elif glyph.isWhitespace:
        flags.incl gfSpace
      let
        shapingSafe = index >= breakAfter.len or breakAfter[index]
        clusterBoundary =
          not hasNext or glyph.source != arrangement.arrangedGlyphs[index + 1].source
      if clusterBoundary and gfSoftHyphen notin flags:
        flags.incl gfCluster
      if shapingSafe and clusterBoundary:
        flags.incl gfSafe
      if shapingSafe and gfSoftHyphen notin flags:
        if gfSpace in flags or last.canBreakAfterRune:
          flags.incl gfPreferred
          if last.isHyphenRune:
            flags.incl gfExplicitHyphen
        elif hasNext and last.isCjkLineBreakRune and nextFirst.isCjkLineBreakRune and
            glyph.source.runeEnd ==
            arrangement.arrangedGlyphs[index + 1].source.runeStart:
          flags.incl gfPreferred
      ctx.flags[index] = flags
      ctx.widths[index] = arrangement.arrangedGlyphs[index].glyphWrapWidth()

proc hyphenFor(ctx: var LayoutContext, fontId: FontId): HyphenGlyph =
  if ctx.resolver.isNil:
    return
  if fontId notin ctx.hyphens:
    ctx.hyphens[fontId] = ctx.resolver(fontId)
  ctx.hyphens[fontId]

func lineIndent(style: ParagraphStyle, first: bool): float32 =
  if first: style.firstLineIndent else: style.headIndent

func available(ctx: LayoutContext, style: ParagraphStyle, first: bool): float32 =
  max(ctx.boxWidth - style.lineIndent(first) - style.tailIndent, 0)

proc patternPoints(ctx: var LayoutContext, language, word: string): seq[int] =
  if language notin ctx.patterns:
    var lookup: PatternLookup
    lookup.found = hyphenationPatternsFor(language, lookup.patterns)
    ctx.patterns[language] = lookup
  let lookup = ctx.patterns[language]
  if lookup.found:
    result = lookup.patterns[].hyphenationPoints(word)

proc wordHyphenPoints(
    ctx: var LayoutContext,
    arrangement: GlyphArrangement,
    paragraph: LayoutParagraph,
    wordStart, wordEnd: int,
    hyphenate: bool,
): seq[HyphenPoint] =
  ## Ascending breaks inside a word: after soft hyphens, or else after glyphs
  ## at registered hyphenation points when `hyphenate` is set.
  for index in wordStart .. wordEnd:
    if gfSoftHyphen in ctx.flags[index]:
      result.add (index, heSoftHyphen)
  if result.len > 0 or not hyphenate or wordStart >= wordEnd:
    return
  let source = arrangement.sourceRunes
  if source.isNil:
    return
  for index in wordStart ..< wordEnd:
    if arrangement.arrangedGlyphs[index + 1].source.runeStart <
        arrangement.arrangedGlyphs[index].source.runeStart:
      return
  # Hyphenate the alphabetic core, leaving quotes and punctuation attached.
  var
    first = wordStart
    last = wordEnd
  while first <= last and
      not arrangement.firstSourceRune(arrangement.arrangedGlyphs[first]).isAlpha:
    inc first
  while last >= first and
      not arrangement.lastSourceRune(arrangement.arrangedGlyphs[last]).isAlpha:
    dec last
  if first >= last:
    return
  let
    byteStart = arrangement.arrangedGlyphs[first].source.byteStart
    byteEnd = arrangement.arrangedGlyphs[last].source.byteEnd
    runeStart = arrangement.arrangedGlyphs[first].source.runeStart
    key = paragraph.language & '\0' & source.bytes[byteStart ..< byteEnd]
  if key notin ctx.wordPoints:
    ctx.wordPoints[key] =
      ctx.patternPoints(paragraph.language, key[paragraph.language.len + 1 .. ^1])
  let points = ctx.wordPoints[key]
  var pointIndex = 0
  for index in first ..< last:
    let boundary = arrangement.arrangedGlyphs[index + 1].source.runeStart - runeStart
    while pointIndex < points.len and points[pointIndex] < boundary:
      inc pointIndex
    if pointIndex < points.len and points[pointIndex] == boundary and
        gfSafe in ctx.flags[index]:
      result.add (index, heInsert)

proc hyphenWidth(
    ctx: var LayoutContext, arrangement: GlyphArrangement, index: int
): float32 =
  let hyphen = ctx.hyphenFor(arrangement.arrangedGlyphs[index].fontId)
  if hyphen.found: hyphen.advance else: -1

proc greedyLines(
    ctx: var LayoutContext,
    arrangement: GlyphArrangement,
    paragraph: LayoutParagraph,
    lines: var seq[BrokenLine],
) =
  ## Fills each line in turn. Word bounds and hyphenation points are found
  ## once per word, so long unbroken text stays linear.
  let range = paragraph.glyphs
  var
    lineStart = range.a
    lineWidth = 0.0'f32
    lastBreak = -1
    lastSafe = -1
    lastCluster = -1
    index = range.a
    firstLine = true
    wordStart = range.a ## First glyph of the word holding `index`.
    pointsWord = -1
    points: seq[HyphenPoint]
  while index <= range.b:
    let width = ctx.widths[index]
    let available = ctx.available(paragraph.style, firstLine)
    if index > lineStart and gfSpace notin ctx.flags[index] and
        lineWidth + width > available:
      var
        cut = -1
        edit = heNone
      if pointsWord != wordStart:
        var wordEnd = index
        while wordEnd < range.b and gfSpace notin ctx.flags[wordEnd + 1] and
            gfPreferred notin ctx.flags[wordEnd]:
          inc wordEnd
        points = ctx.wordHyphenPoints(
          arrangement, paragraph, wordStart, wordEnd, paragraph.style.hyphenate
        )
        pointsWord = wordStart
      if points.len > 0:
        var
          tailWidth = 0.0'f32
          pointIndex = points.high
          candidate = index - 1
        while candidate >= max(wordStart, lineStart) and pointIndex >= 0:
          while pointIndex >= 0 and points[pointIndex].index > candidate:
            dec pointIndex
          if pointIndex >= 0 and points[pointIndex].index == candidate:
            let
              hyphen = ctx.hyphenWidth(arrangement, candidate)
              shown = max(hyphen, 0)
            if lineWidth - tailWidth + shown <= available:
              cut = candidate
              # Without a hyphen glyph a soft hyphen is a plain break.
              edit =
                if hyphen >= 0:
                  points[pointIndex].edit
                else:
                  heNone
              if hyphen < 0 and edit == heNone and points[pointIndex].edit == heInsert:
                cut = -1
              else:
                break
          tailWidth += ctx.widths[candidate]
          dec candidate
      if cut < 0:
        if lastBreak >= lineStart:
          cut = lastBreak
        elif lastSafe >= lineStart:
          cut = lastSafe
        elif lastCluster >= lineStart:
          # Overflowing the box is worse than breaking where shaping across
          # the boundary differs, e.g. between kerned glyphs.
          cut = lastCluster
      if cut >= lineStart:
        lines.add BrokenLine(glyphs: lineStart .. cut, edit: edit)
        if ctx.flags[cut] * {gfSpace, gfPreferred} != {}:
          wordStart = cut + 1
        lineStart = cut + 1
        lineWidth = 0
        lastBreak = -1
        lastSafe = -1
        lastCluster = -1
        index = lineStart
        firstLine = false
        continue
    lineWidth += width
    let flags = ctx.flags[index]
    # Discretionary hyphens break only where their hyphen is shown.
    if gfSafe in flags and gfSoftHyphen notin flags:
      lastSafe = index
    if gfCluster in flags:
      lastCluster = index
    if gfPreferred in flags:
      lastBreak = index
    if flags * {gfSpace, gfPreferred} != {}:
      wordStart = index + 1
    inc index
  if lineStart <= range.b:
    lines.add BrokenLine(glyphs: lineStart .. range.b)

type
  BreakCandidate = object
    contentEnd: int ## Last glyph whose width counts toward the line.
    next: int ## First glyph of the following line.
    extraWidth: float32 ## Visible hyphen width added at the break.
    penalty: float64
    flagged: bool ## A hyphen ends the line.
    forced: bool
    edit: HyphenEdit

  BreakNode = object
    candidate: int ## Index into candidates; -1 for the paragraph start.
    line: int ## Lines set before this break.
    fitness: int
    demerits: float64
    previous: int
    flagged: bool

proc breakCandidates(
    ctx: var LayoutContext,
    arrangement: GlyphArrangement,
    paragraph: LayoutParagraph,
    hyphenate: bool,
): seq[BreakCandidate] =
  let range = paragraph.glyphs
  var
    index = range.a
    wordStart = range.a
  while index <= range.b:
    let flags = ctx.flags[index]
    if gfSpace in flags:
      var runEnd = index
      while runEnd < range.b and gfSpace in ctx.flags[runEnd + 1]:
        inc runEnd
      if runEnd < range.b and index > range.a:
        result.add BreakCandidate(contentEnd: index - 1, next: runEnd + 1)
      index = runEnd + 1
      wordStart = index
      continue
    if index < range.b and gfPreferred in flags:
      result.add BreakCandidate(
        contentEnd: index,
        next: index + 1,
        penalty: (if gfExplicitHyphen in flags: HyphenPenalty else: 0.0),
        flagged: gfExplicitHyphen in flags,
      )
    if gfPreferred in flags or index == range.b or gfSpace in ctx.flags[index + 1]:
      # Soft hyphens always qualify; pattern points only when `hyphenate`.
      for (point, edit) in ctx.wordHyphenPoints(
        arrangement, paragraph, wordStart, index, hyphenate
      ):
        if point >= index:
          continue
        let hyphen = ctx.hyphenWidth(arrangement, point)
        if hyphen >= 0:
          result.add BreakCandidate(
            contentEnd: point,
            next: point + 1,
            extraWidth: hyphen,
            penalty: HyphenPenalty,
            flagged: true,
            edit: edit,
          )
        elif edit == heSoftHyphen:
          result.add BreakCandidate(contentEnd: point, next: point + 1)
      wordStart = index + 1
    inc index
  result.sort(
    proc(a, b: BreakCandidate): int =
      cmp(a.contentEnd, b.contentEnd)
  )
  var trailing = range.b
  while trailing > range.a and gfSpace in ctx.flags[trailing]:
    dec trailing
  result.add BreakCandidate(contentEnd: trailing, next: range.b + 1, forced: true)

proc optimalLines(
    ctx: var LayoutContext,
    arrangement: GlyphArrangement,
    paragraph: LayoutParagraph,
    hyphenate: bool,
    tolerance: float64,
    lines: var seq[BrokenLine],
): bool =
  ## Knuth-Plass total-fit breaking with spaces as stretchable glue.
  let range = paragraph.glyphs
  let candidates = ctx.breakCandidates(arrangement, paragraph, hyphenate)
  let count = range.b - range.a + 1
  var widths, stretch, shrink = newSeq[float64](count + 1)
  for offset in 0 ..< count:
    let index = range.a + offset
    widths[offset + 1] = widths[offset] + ctx.widths[index].float64
    stretch[offset + 1] = stretch[offset]
    shrink[offset + 1] = shrink[offset]
    if gfSpace in ctx.flags[index]:
      stretch[offset + 1] += ctx.widths[index] * JustifyStretch
      shrink[offset + 1] += ctx.widths[index] * JustifyShrink
  let justifiesLast = paragraph.style.lastLineAlign == paJustify
  var
    nodes = @[BreakNode(candidate: -1, fitness: 1, previous: -1)]
    active = @[0]
  for candidateIndex, candidate in candidates:
    var
      best: array[4, float64] = [Inf, Inf, Inf, Inf]
      bestPrevious: array[4, int]
    var kept = newSeqOfCap[int](active.len)
    for nodeIndex in active:
      let
        node = nodes[nodeIndex]
        start =
          if node.candidate < 0:
            range.a
          else:
            candidates[node.candidate].next
        target = ctx.available(paragraph.style, node.line == 0).float64
      if candidate.contentEnd < start:
        kept.add nodeIndex
        continue
      let
        first = start - range.a
        stop = candidate.contentEnd - range.a + 1
        natural = widths[stop] - widths[first] + candidate.extraWidth
        lineStretch = stretch[stop] - stretch[first]
        lineShrink = shrink[stop] - shrink[first]
        # A last line set at natural width cannot shrink to fit.
        canAdjust = not candidate.forced or justifiesLast
        ratio =
          if natural < target:
            if candidate.forced and not justifiesLast:
              0.0
            elif lineStretch > 0:
              (target - natural) / lineStretch
            elif candidate.forced:
              0.0
            else:
              Inf
          elif natural > target:
            if canAdjust and lineShrink > 0:
              (target - natural) / lineShrink
            else:
              -Inf
          else:
            0.0
      if ratio < -1.0:
        continue # Later breaks only lengthen this line.
      kept.add nodeIndex
      if ratio > tolerance:
        continue
      let
        badness = min(100.0 * pow(abs(ratio), 3.0), 10000.0)
        fitness =
          if ratio < -0.5:
            0
          elif ratio <= 0.5:
            1
          elif ratio <= 1.0:
            2
          else:
            3
      var demerits = pow(LinePenalty + badness, 2.0)
      if candidate.penalty > 0:
        demerits += candidate.penalty * candidate.penalty
      if candidate.flagged and node.flagged:
        demerits += DoubleHyphenDemerits
      if abs(fitness - node.fitness) > 1:
        demerits += AdjacentFitnessDemerits
      let total = node.demerits + demerits
      if total < best[fitness]:
        best[fitness] = total
        bestPrevious[fitness] = nodeIndex
    active = kept
    # Every break after the first sets later lines with the head indent, so
    # nodes need no line-number classes beyond fitness.
    for fitness in 0 .. 3:
      if best[fitness] < Inf:
        let previous = bestPrevious[fitness]
        nodes.add BreakNode(
          candidate: candidateIndex,
          line: nodes[previous].line + 1,
          fitness: fitness,
          demerits: best[fitness],
          previous: previous,
          flagged: candidate.flagged,
        )
        if not candidate.forced:
          active.add nodes.high
    if active.len == 0 and not candidate.forced:
      return false
  var
    bestNode = -1
    bestDemerits = Inf
  for nodeIndex, node in nodes:
    if node.candidate == candidates.high and node.demerits < bestDemerits:
      bestNode = nodeIndex
      bestDemerits = node.demerits
  if bestNode < 0:
    return false
  var chain: seq[int]
  var cursor = bestNode
  while cursor > 0:
    chain.add cursor
    cursor = nodes[cursor].previous
  var start = range.a
  for position in countdown(chain.high, 0):
    let candidate = candidates[nodes[chain[position]].candidate]
    let stop =
      if candidate.forced:
        range.b
      else:
        candidate.next - 1
    lines.add BrokenLine(glyphs: start .. stop, edit: candidate.edit)
    start = candidate.next
  true

proc hyphenRecord(
    ctx: var LayoutContext, base: GlyphRecord, rect: Rect, visualKey: float64
): GlyphRecord =
  ## A visible hyphen styled like `base`, keeping its decorations.
  let hyphen = ctx.hyphenFor(base.glyph.fontId)
  result = base
  result.font =
    if hyphen.glyphFont.fontId == base.font.fontId:
      base.font
    else:
      var font = hyphen.glyphFont
      font.underline = base.font.underline
      font.strikethrough = base.font.strikethrough
      font
  result.glyph.fontId = hyphen.glyphFont.fontId
  result.glyph.glyphId = hyphen.glyphId
  result.glyph.rune = Rune('-')
  result.glyph.isWhitespace = false
  result.glyph.advance = vec2(hyphen.advance, 0)
  result.glyph.offset = vec2(0, 0)
  result.glyph.imageOffset = hyphen.imageOffset
  result.glyph.pos = vec2(rect.x, base.glyph.pos.y)
  result.glyph.rect = rect
  result.glyph.rect.w = hyphen.advance
  result.selection = result.glyph.rect
  result.visualKey = visualKey

proc finishLines(
    ctx: var LayoutContext,
    arrangement: var GlyphArrangement,
    lines: var seq[BrokenLine],
    owners: openArray[int],
    reordered: openArray[bool],
    records: var seq[GlyphRecord],
) =
  ## Shows hyphens at the line ends that need them and restores display order
  ## within lines of reordered paragraphs. Inserted hyphens share the source
  ## range of the glyph they follow, so selection treats them as part of that
  ## cluster.
  var
    edited = false
    anyReordered = false
  for line in lines:
    if line.edit != heNone:
      edited = true
  for flag in reordered:
    anyReordered = anyReordered or flag
  if not edited and not anyReordered:
    return
  if records.len != arrangement.arrangedGlyphs.len:
    records = arrangement.decompose()
  else:
    # Records predate classification, which hides soft hyphens.
    for index, glyph in arrangement.arrangedGlyphs:
      records[index].glyph = glyph
      records[index].selection = arrangement.selectionRects[index]

  var output = newSeqOfCap[GlyphRecord](records.len + lines.len)
  var remapped = newSeq[BrokenLine](lines.len)
  var order = newSeq[int](lines.len)
  for index in 0 ..< lines.len:
    order[index] = index
  # Emit lines by glyph position so every glyph is copied exactly once.
  var starts = newSeq[int](lines.len)
  for index, line in lines:
    starts[index] = line.glyphs.a
  order.sort(
    proc(a, b: int): int =
      cmp(starts[a], starts[b])
  )
  var cursor = 0
  for lineIndex in order:
    let line = lines[lineIndex]
    while cursor < line.glyphs.a:
      output.add records[cursor]
      inc cursor
    let start = output.len
    for index in line.glyphs:
      var record = records[index]
      if index == line.glyphs.b and line.edit == heSoftHyphen:
        record = ctx.hyphenRecord(record, record.selection, record.visualKey)
      output.add record
      if index == line.glyphs.b and line.edit == heInsert:
        # The hyphen follows its glyph in reading order: visually after it in
        # left-to-right runs and before it in right-to-left runs.
        let
          next = min(index + 1, records.high)
          leftward = next != index and records[next].visualKey < record.visualKey
          key = record.visualKey + (if leftward: -0.5 else: 0.5)
          base = output[^1]
        output.add ctx.hyphenRecord(
          base,
          rect(
            base.selection.x + base.selection.w, base.selection.y, 0, base.selection.h
          ),
          key,
        )
    cursor = line.glyphs.b + 1
    if reordered[owners[lineIndex]]:
      var slice = output[start .. output.high]
      slice.sort(
        proc(a, b: GlyphRecord): int =
          cmp(a.visualKey, b.visualKey)
      )
      for offset, record in slice:
        output[start + offset] = record
    remapped[lineIndex] = BrokenLine(glyphs: start .. output.high)
  while cursor < records.len:
    output.add records[cursor]
    inc cursor
  lines = remapped
  arrangement.recompose(output)

proc breakParagraphLines*(
    arrangement: var GlyphArrangement,
    paragraphs: openArray[LayoutParagraph],
    breakAfter: openArray[bool],
    boxWidth: float32,
    wrap: bool,
    resolver: HyphenResolver,
): seq[ParagraphLine] =
  ## Breaks every paragraph into `arrangement.lines` in reading order, showing
  ## hyphens where words break. Bidirectional paragraphs break in source order
  ## and keep display order within each line. `breakAfter` marks shaping-safe
  ## breaks in display order; empty means all. Returns one entry per line.
  var ctx = LayoutContext(resolver: resolver, boxWidth: boxWidth, wrap: wrap)
  var
    records: seq[GlyphRecord]
    reordered: seq[bool]
  let safe = arrangement.orderLogically(paragraphs, breakAfter, records, reordered)
  ctx.classifyGlyphs(arrangement, paragraphs, safe)
  let wraps = wrap and boxWidth > 0
  var
    lines: seq[BrokenLine]
    owners: seq[int]
  for paragraphIndex, paragraph in paragraphs:
    let range = paragraph.glyphs
    if range.a > range.b:
      continue
    var paragraphLines: seq[BrokenLine]
    if not wraps:
      paragraphLines.add BrokenLine(glyphs: range)
    else:
      var placed = false
      if paragraph.style.lineBreaking == plbOptimal and
          paragraph.style.align == paJustify:
        placed = ctx.optimalLines(arrangement, paragraph, false, 1.0, paragraphLines)
        if not placed:
          paragraphLines.setLen(0)
          placed = ctx.optimalLines(
            arrangement, paragraph, paragraph.style.hyphenate, 2.0, paragraphLines
          )
        if not placed:
          paragraphLines.setLen(0)
          placed = ctx.optimalLines(
            arrangement, paragraph, paragraph.style.hyphenate, 10.0, paragraphLines
          )
        if not placed:
          paragraphLines.setLen(0)
      if not placed:
        ctx.greedyLines(arrangement, paragraph, paragraphLines)
    for line in paragraphLines:
      lines.add line
      owners.add paragraphIndex
  ctx.finishLines(arrangement, lines, owners, reordered, records)
  arrangement.lines.setLen(0)
  var previousOwner = -1
  for lineIndex, line in lines:
    let owner = owners[lineIndex]
    arrangement.lines.add line.glyphs
    result.add ParagraphLine(
      paragraph: owner,
      first: owner != previousOwner,
      last: lineIndex == lines.high or owners[lineIndex + 1] != owner,
      rtl: paragraphs[owner].rightToLeft,
    )
    previousOwner = owner

proc lineHeight*(arrangement: GlyphArrangement, line: Slice[int]): float32 =
  for glyphIndex in line:
    result = max(result, arrangement.arrangedGlyphs[glyphIndex].rect.h)
  if result <= 0:
    for font in arrangement.fonts:
      result = max(result, font.lineHeight)

func justifies(style: ParagraphStyle, line: ParagraphLine): bool =
  style.align == paJustify and (not line.last or style.lastLineAlign == paJustify)

proc withoutTrailingSpace(
    arrangement: GlyphArrangement, line: Slice[int], rtl: bool
): Slice[int] =
  ## The line without whitespace at its reading end, which hangs past the
  ## measure: the right end of a left-to-right line, else the left end.
  result = line
  if rtl:
    while result.a <= result.b and arrangement.arrangedGlyphs[result.a].isWhitespace:
      inc result.a
  else:
    while result.b >= result.a and arrangement.arrangedGlyphs[result.b].isWhitespace:
      dec result.b

proc stretchableSpaces(
    arrangement: GlyphArrangement, line: Slice[int], rtl: bool
): Slice[int] =
  ## Glyphs between the line's first and last visible glyphs; leading and
  ## hanging whitespace keep their natural widths.
  result = arrangement.withoutTrailingSpace(line, rtl)
  while result.a <= result.b and arrangement.arrangedGlyphs[result.a].isWhitespace:
    inc result.a
  while result.b >= result.a and arrangement.arrangedGlyphs[result.b].isWhitespace:
    dec result.b

proc reflowParagraphLines*(
    arrangement: var GlyphArrangement,
    lines: openArray[ParagraphLine],
    paragraphs: openArray[LayoutParagraph],
    boxWidth: float32,
    wrap: bool,
) =
  ## Stacks lines with line and paragraph spacing, packing each line's glyphs
  ## left to right and stretching interior spaces of justified lines.
  var lineTop = 0.0'f32
  for lineIndex, line in arrangement.lines:
    var
      extraPerSpace = 0.0'f32
      stretchable = 1 .. 0
    if lineIndex < lines.len:
      let
        info = lines[lineIndex]
        style = paragraphs[info.paragraph].style
      if info.first and lineIndex > 0:
        lineTop +=
          paragraphs[lines[lineIndex - 1].paragraph].style.spacingAfter +
          style.spacingBefore
      if wrap and boxWidth > 0 and style.justifies(info):
        stretchable = arrangement.stretchableSpaces(line, info.rtl)
        var
          width = 0.0'f32
          spaces = 0
          narrowestSpace = float32.high
        for glyphIndex in arrangement.withoutTrailingSpace(line, info.rtl):
          width += arrangement.arrangedGlyphs[glyphIndex].glyphWrapWidth()
        for glyphIndex in stretchable:
          let glyph = arrangement.arrangedGlyphs[glyphIndex]
          if glyph.isWhitespace and glyph.rect.w > 0:
            inc spaces
            narrowestSpace = min(narrowestSpace, glyph.glyphWrapWidth())
        let target = max(boxWidth - style.lineIndent(info.first) - style.tailIndent, 0)
        if spaces > 0:
          # Shrink no further than optimal breaking allows, so words never
          # run together when the measure is narrower than the line.
          extraPerSpace =
            max((target - width) / spaces.float32, -narrowestSpace * JustifyShrink)
    let height = arrangement.lineHeight(line)
    var lineX = 0.0'f32
    for glyphIndex in line:
      let
        oldGlyph = arrangement.arrangedGlyphs[glyphIndex]
        posOffset = oldGlyph.pos - oldGlyph.rect.xy
        stretched =
          extraPerSpace != 0 and glyphIndex in stretchable and oldGlyph.isWhitespace and
          oldGlyph.rect.w > 0
        width = oldGlyph.glyphWrapWidth() + (if stretched: extraPerSpace else: 0)
        newRect = rect(
          lineX, lineTop, (if stretched: width else: oldGlyph.rect.w), oldGlyph.rect.h
        )
        newPos = newRect.xy + posOffset
      arrangement.arrangedGlyphs[glyphIndex].rect = newRect
      arrangement.arrangedGlyphs[glyphIndex].pos = newPos
      arrangement.positions[glyphIndex] = newPos
      arrangement.selectionRects[glyphIndex] = newRect
      lineX += width
    lineTop += height
    if lineIndex < lines.len:
      lineTop += paragraphs[lines[lineIndex].paragraph].style.lineSpacing

proc shiftGlyph(arrangement: var GlyphArrangement, glyphIndex: int, delta: Vec2) =
  arrangement.arrangedGlyphs[glyphIndex].pos += delta
  arrangement.arrangedGlyphs[glyphIndex].rect =
    arrangement.arrangedGlyphs[glyphIndex].rect + rect(delta.x, delta.y, 0, 0)
  arrangement.positions[glyphIndex] += delta
  arrangement.selectionRects[glyphIndex] =
    arrangement.selectionRects[glyphIndex] + rect(delta.x, delta.y, 0, 0)

proc lineBounds(arrangement: GlyphArrangement, line: Slice[int]): Rect =
  result = rect(float32.high, float32.high, 0, 0)
  if line.a > line.b:
    return rect(0, 0, 0, 0)
  for glyphIndex in line:
    let glyphRect = arrangement.arrangedGlyphs[glyphIndex].rect
    result.x = min(result.x, glyphRect.x)
    result.y = min(result.y, glyphRect.y)
    result.w = max(result.w, glyphRect.x + glyphRect.w)
    result.h = max(result.h, glyphRect.y + glyphRect.h)
  result.w -= result.x
  result.h -= result.y

proc alignParagraphLines*(
    arrangement: var GlyphArrangement,
    lines: openArray[ParagraphLine],
    paragraphs: openArray[LayoutParagraph],
    box: Rect,
    hAlign: FontHorizontal,
    vAlign: FontVertical,
) =
  ## Places each line between its paragraph's indents, then aligns the block
  ## vertically in `box`. Indents mirror for right-to-left paragraphs.
  if arrangement.arrangedGlyphs.len == 0:
    return
  let allLines =
    if arrangement.lines.len > 0:
      arrangement.lines
    else:
      @[0 .. arrangement.arrangedGlyphs.len - 1]
  for lineIndex, line in allLines:
    var
      leftEdge = 0.0'f32
      rightEdge = box.w
      align =
        case hAlign
        of Left: paLeft
        of Center: paCenter
        of Right: paRight
      bounds = arrangement.lineBounds(line)
    if lineIndex < lines.len and lines.len == allLines.len:
      let
        info = lines[lineIndex]
        style = paragraphs[info.paragraph].style
        lead = style.lineIndent(info.first)
      if info.rtl:
        leftEdge = style.tailIndent
        rightEdge = box.w - lead
      else:
        leftEdge = lead
        rightEdge = box.w - style.tailIndent
      # Indents wider than the box leave an empty measure at the leading edge.
      if info.rtl:
        leftEdge = min(leftEdge, rightEdge)
      else:
        rightEdge = max(rightEdge, leftEdge)
      if style.align != paInherit:
        align = style.align
      if not info.last or style.justifies(info):
        # Spaces where a line wraps hang past the measure.
        let content = arrangement.withoutTrailingSpace(line, info.rtl)
        if content.a <= content.b:
          bounds = arrangement.lineBounds(content)
      if align == paJustify:
        if style.justifies(info):
          align = if info.rtl: paRight else: paLeft
        else:
          align =
            if style.lastLineAlign notin {paInherit, paJustify}:
              style.lastLineAlign
            elif info.rtl:
              paRight
            else:
              paLeft
    var dx = -bounds.x
    case align
    of paLeft, paInherit, paJustify:
      dx += leftEdge
    of paCenter:
      dx += leftEdge + (rightEdge - leftEdge - bounds.w) / 2
    of paRight:
      dx += rightEdge - bounds.w
    if dx != 0:
      for glyphIndex in line:
        arrangement.shiftGlyph(glyphIndex, vec2(dx, 0))

  let bounds = arrangement.calcMinMaxContent().bounding
  var dy = -bounds.y
  case vAlign
  of Top:
    discard
  of Middle:
    dy += (box.h - bounds.h) / 2
  of Bottom:
    dy += box.h - bounds.h
  if dy != 0:
    for glyphIndex in 0 ..< arrangement.arrangedGlyphs.len:
      arrangement.shiftGlyph(glyphIndex, vec2(0, dy))
