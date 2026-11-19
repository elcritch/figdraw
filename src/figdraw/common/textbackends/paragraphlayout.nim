## Backend-neutral paragraph layout over shaped glyphs: line breaking with
## per-line measures, hyphenation, justification, spacing, and alignment.
##
## Backends shape each paragraph onto one baseline, then describe paragraphs
## as visual glyph ranges. Layout keeps glyph geometry arrays in sync and only
## rebuilds spans and display runes when it inserts hyphen glyphs.

import std/[algorithm, math, tables, unicode]

import pkg/vmath

import ../fonttypes
import ../hyphenation
import ./common

type
  LayoutParagraph* = object
    glyphs*: Slice[int] ## Visual glyph range of one source paragraph; may be empty.
    style*: ParagraphStyle
    language*: string ## BCP 47 language used for hyphenation.

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
    gfPreferred ## Preferred break opportunity after this glyph.
    gfExplicitHyphen ## Break follows a visible hyphen character.

  LayoutContext = object
    flags: seq[set[GlyphFlag]]
    widths: seq[float32]
    hyphens: Table[FontId, HyphenGlyph]
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
      if shapingSafe and clusterBoundary:
        flags.incl gfSafe
      if shapingSafe and gfSoftHyphen notin flags:
        if gfSpace in flags or last.canBreakAfterRune:
          flags.incl gfPreferred
          if last.isHyphenRune:
            flags.incl gfExplicitHyphen
        elif hasNext and last.isCjkLineBreakRune and nextFirst.isCjkLineBreakRune:
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

proc wordHyphenPoints(
    ctx: var LayoutContext,
    arrangement: GlyphArrangement,
    paragraph: LayoutParagraph,
    wordStart, wordEnd: int,
): seq[tuple[index: int, edit: HyphenEdit]] =
  ## Ascending breaks inside a word: after soft hyphens, or else after glyphs
  ## at registered hyphenation points. Right-to-left words are not hyphenated.
  for index in wordStart .. wordEnd:
    if gfSoftHyphen in ctx.flags[index]:
      result.add (index, heSoftHyphen)
  if result.len > 0 or not paragraph.style.hyphenate or wordStart >= wordEnd:
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
      hyphenationPoints(paragraph.language, key[paragraph.language.len + 1 .. ^1])
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
  let range = paragraph.glyphs
  var
    lineStart = range.a
    lineWidth = 0.0'f32
    lastBreak = -1
    lastSafe = -1
    index = range.a
    firstLine = true
  while index <= range.b:
    let width = ctx.widths[index]
    if index > lineStart and gfSpace notin ctx.flags[index] and
        lineWidth + width > ctx.available(paragraph.style, firstLine):
      let available = ctx.available(paragraph.style, firstLine)
      var
        cut = -1
        edit = heNone
      # Hyphenate the whole word, even when an earlier line holds part of it.
      var wordStart = index
      while wordStart > range.a and gfSpace notin ctx.flags[wordStart - 1] and
          gfPreferred notin ctx.flags[wordStart - 1]:
        dec wordStart
      var wordEnd = index
      while wordEnd < range.b and gfSpace notin ctx.flags[wordEnd + 1] and
          gfPreferred notin ctx.flags[wordEnd]:
        inc wordEnd
      let points = ctx.wordHyphenPoints(arrangement, paragraph, wordStart, wordEnd)
      if points.len > 0:
        var
          tailWidth = 0.0'f32
          pointIndex = points.high
          candidate = index - 1
        while candidate >= max(wordStart, lineStart) and pointIndex >= 0:
          while pointIndex >= 0 and points[pointIndex].index > candidate:
            dec pointIndex
          if pointIndex >= 0 and points[pointIndex].index == candidate:
            let hyphen = ctx.hyphenWidth(arrangement, candidate)
            if hyphen >= 0 and lineWidth - tailWidth + hyphen <= available:
              cut = candidate
              edit = points[pointIndex].edit
              break
          tailWidth += ctx.widths[candidate]
          dec candidate
      if cut < 0:
        if lastBreak >= lineStart:
          cut = lastBreak
        elif lastSafe >= lineStart:
          cut = lastSafe
      if cut >= lineStart:
        lines.add BrokenLine(glyphs: lineStart .. cut, edit: edit)
        lineStart = cut + 1
        lineWidth = 0
        lastBreak = -1
        lastSafe = -1
        index = lineStart
        firstLine = false
        continue
    lineWidth += width
    let flags = ctx.flags[index]
    if gfSafe in flags:
      lastSafe = index
    if gfPreferred in flags:
      lastBreak = index
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
      var wordParagraph = paragraph
      wordParagraph.style.hyphenate = hyphenate
      for (point, edit) in ctx.wordHyphenPoints(
        arrangement, wordParagraph, wordStart, index
      ):
        let hyphen = ctx.hyphenWidth(arrangement, point)
        if hyphen >= 0 and point < index:
          result.add BreakCandidate(
            contentEnd: point,
            next: point + 1,
            extraWidth: hyphen,
            penalty: HyphenPenalty,
            flagged: true,
            edit: edit,
          )
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
  var
    nodes = @[BreakNode(candidate: -1, fitness: 1, previous: -1)]
    active = @[0]
  for candidateIndex, candidate in candidates:
    var
      best: array[4, array[2, float64]]
      bestPrevious: array[4, array[2, int]]
    for fitness in 0 .. 3:
      for lineClass in 0 .. 1:
        best[fitness][lineClass] = Inf
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
        ratio =
          if natural < target:
            if candidate.forced:
              0.0
            elif stretch[stop] - stretch[first] > 0:
              (target - natural) / (stretch[stop] - stretch[first])
            else:
              Inf
          elif natural > target:
            if shrink[stop] - shrink[first] > 0:
              (target - natural) / (shrink[stop] - shrink[first])
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
      let
        total = node.demerits + demerits
        lineClass = min(node.line + 1, 1)
      if total < best[fitness][lineClass]:
        best[fitness][lineClass] = total
        bestPrevious[fitness][lineClass] = nodeIndex
    active = kept
    for fitness in 0 .. 3:
      for lineClass in 0 .. 1:
        if best[fitness][lineClass] < Inf:
          let previous = bestPrevious[fitness][lineClass]
          nodes.add BreakNode(
            candidate: candidateIndex,
            line: nodes[previous].line + 1,
            fitness: fitness,
            demerits: best[fitness][lineClass],
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

func lineSourceStart(arrangement: GlyphArrangement, line: Slice[int]): int =
  result = high(int)
  for glyphIndex in line:
    let source = arrangement.arrangedGlyphs[glyphIndex].source
    if source.runeStart < source.runeEnd:
      result = min(result, source.runeStart)
  if result == high(int):
    result = 0

func linesNeedLogicalReverse(
    arrangement: GlyphArrangement, lines: openArray[BrokenLine]
): bool =
  if lines.len < 2:
    return false
  var previous = arrangement.lineSourceStart(lines[0].glyphs)
  for i in 1 ..< lines.len:
    let current = arrangement.lineSourceStart(lines[i].glyphs)
    if current < previous:
      return true
    if current > previous:
      return false
    previous = current

func lineRunsRightToLeft(arrangement: GlyphArrangement, line: Slice[int]): bool =
  var
    first = -1
    last = -1
  for index in line:
    let source = arrangement.arrangedGlyphs[index].source
    if source.runeStart < source.runeEnd:
      if first < 0:
        first = source.runeStart
      last = source.runeStart
  first >= 0 and last < first

proc applyHyphenEdits(
    ctx: var LayoutContext,
    arrangement: var GlyphArrangement,
    lines: var seq[BrokenLine],
) =
  ## Shows hyphens at the line ends that need them. Inserted glyphs share the
  ## source range of the glyph they follow, so selection treats them as part
  ## of its cluster.
  var
    edited = false
    inserts = 0
  for line in lines:
    case line.edit
    of heNone:
      discard
    of heSoftHyphen, heInsert:
      edited = true
      if line.edit == heInsert:
        inc inserts
  if not edited:
    return

  let count = arrangement.arrangedGlyphs.len
  var
    glyphFonts = newSeq[GlyphFont](count)
    glyphColors = newSeq[Fill](count)
    covered = newSeq[bool](count)
    endEdits = newSeq[HyphenEdit](count)
    newIndex = newSeq[int](count)
  for spanIndex, span in arrangement.spans:
    for glyphIndex in span:
      if glyphIndex in 0 ..< count:
        glyphFonts[glyphIndex] = arrangement.fonts[spanIndex]
        glyphColors[glyphIndex] = arrangement.spanColors[spanIndex]
        covered[glyphIndex] = true
  for line in lines:
    if line.glyphs.b in 0 ..< count:
      endEdits[line.glyphs.b] = line.edit

  proc hyphenGlyph(
      ctx: var LayoutContext, base: ArrangedGlyph, rect: Rect
  ): (ArrangedGlyph, Rect, GlyphFont) =
    let hyphen = ctx.hyphenFor(base.fontId)
    var glyph = base
    glyph.fontId = hyphen.glyphFont.fontId
    glyph.glyphId = hyphen.glyphId
    glyph.rune = Rune('-')
    glyph.isWhitespace = false
    glyph.advance = vec2(hyphen.advance, 0)
    glyph.offset = vec2(0, 0)
    glyph.imageOffset = hyphen.imageOffset
    glyph.pos = vec2(rect.x, base.pos.y)
    var hyphenRect = rect
    hyphenRect.w = hyphen.advance
    glyph.rect = hyphenRect
    (glyph, hyphenRect, hyphen.glyphFont)

  let total = count + inserts
  var
    glyphs = newSeqOfCap[ArrangedGlyph](total)
    positions = newSeqOfCap[Vec2](total)
    rects = newSeqOfCap[Rect](total)
    fonts = newSeqOfCap[GlyphFont](total)
    colors = newSeqOfCap[Fill](total)
    coverage = newSeqOfCap[bool](total)
  for index in 0 ..< count:
    newIndex[index] = glyphs.len
    var
      current = arrangement.arrangedGlyphs[index]
      currentRect = arrangement.selectionRects[index]
      currentFont = glyphFonts[index]
    if endEdits[index] == heSoftHyphen:
      (current, currentRect, currentFont) = ctx.hyphenGlyph(current, currentRect)
    glyphs.add current
    positions.add current.pos
    rects.add currentRect
    fonts.add currentFont
    colors.add glyphColors[index]
    coverage.add covered[index]
    if endEdits[index] == heInsert:
      let (hyphen, hyphenRect, hyphenFont) = ctx.hyphenGlyph(
        current, rect(currentRect.x + currentRect.w, currentRect.y, 0, currentRect.h)
      )
      glyphs.add hyphen
      positions.add hyphen.pos
      rects.add hyphenRect
      fonts.add hyphenFont
      colors.add glyphColors[index]
      coverage.add covered[index]
  for line in lines.mitems:
    let stop = newIndex[line.glyphs.b] + (if line.edit == heInsert: 1 else: 0)
    line.glyphs = newIndex[line.glyphs.a] .. stop

  arrangement.arrangedGlyphs = move glyphs
  arrangement.positions = move positions
  arrangement.selectionRects = move rects
  arrangement.spans.setLen(0)
  arrangement.fonts.setLen(0)
  arrangement.spanColors.setLen(0)
  for index in 0 ..< fonts.len:
    if not coverage[index]:
      continue
    if arrangement.spans.len > 0 and arrangement.spans[^1].b == index - 1 and
        arrangement.fonts[^1] == fonts[index] and
        arrangement.spanColors[^1] == colors[index]:
      arrangement.spans[^1].b = index
    else:
      arrangement.spans.add index .. index
      arrangement.fonts.add fonts[index]
      arrangement.spanColors.add colors[index]
  var display = newStringOfCap(arrangement.arrangedGlyphs.len)
  for glyph in arrangement.arrangedGlyphs:
    display.add glyph.rune
  arrangement.runes = initArrangementRunes(display)

proc breakParagraphLines*(
    arrangement: var GlyphArrangement,
    paragraphs: openArray[LayoutParagraph],
    breakAfter: openArray[bool],
    boxWidth: float32,
    wrap: bool,
    resolver: HyphenResolver,
): seq[ParagraphLine] =
  ## Breaks every paragraph into `arrangement.lines`, showing hyphens where
  ## words break. `breakAfter` marks shaping-safe breaks; empty means all.
  ## Returns one entry per line in `arrangement.lines`.
  var ctx = LayoutContext(resolver: resolver, boxWidth: boxWidth, wrap: wrap)
  ctx.classifyGlyphs(arrangement, paragraphs, breakAfter)
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
    if arrangement.linesNeedLogicalReverse(paragraphLines):
      paragraphLines.reverse()
    for line in paragraphLines:
      lines.add line
      owners.add paragraphIndex
  ctx.applyHyphenEdits(arrangement, lines)
  arrangement.lines.setLen(0)
  var previousOwner = -1
  for lineIndex, line in lines:
    let owner = owners[lineIndex]
    arrangement.lines.add line.glyphs
    result.add ParagraphLine(
      paragraph: owner,
      first: owner != previousOwner,
      last: lineIndex == lines.high or owners[lineIndex + 1] != owner,
    )
    previousOwner = owner
  var lineIndex = 0
  while lineIndex < result.len:
    var stop = lineIndex
    while stop < result.high and
        result[stop + 1].paragraph == result[lineIndex].paragraph:
      inc stop
    var rtl = false
    if stop > lineIndex:
      rtl =
        arrangement.lineSourceStart(arrangement.lines[stop]) <
        arrangement.lineSourceStart(arrangement.lines[lineIndex]) or
        arrangement.lineRunsRightToLeft(arrangement.lines[lineIndex])
    else:
      rtl = arrangement.lineRunsRightToLeft(arrangement.lines[lineIndex])
    for index in lineIndex .. stop:
      result[index].rtl = rtl
    lineIndex = stop + 1

proc lineHeight*(arrangement: GlyphArrangement, line: Slice[int]): float32 =
  for glyphIndex in line:
    result = max(result, arrangement.arrangedGlyphs[glyphIndex].rect.h)
  if result <= 0:
    for font in arrangement.fonts:
      result = max(result, font.lineHeight)

func justifies(style: ParagraphStyle, line: ParagraphLine): bool =
  style.align == paJustify and (not line.last or style.lastLineAlign == paJustify)

proc contentRange(arrangement: GlyphArrangement, line: Slice[int]): Slice[int] =
  ## The line without leading or trailing whitespace.
  result = line
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
    var extraPerSpace = 0.0'f32
    var content = line
    if lineIndex < lines.len:
      let
        info = lines[lineIndex]
        style = paragraphs[info.paragraph].style
      if info.first and lineIndex > 0:
        lineTop +=
          paragraphs[lines[lineIndex - 1].paragraph].style.spacingAfter +
          style.spacingBefore
      if wrap and boxWidth > 0 and style.justifies(info):
        content = arrangement.contentRange(line)
        var
          width = 0.0'f32
          spaces = 0
          narrowestSpace = float32.high
        for glyphIndex in content:
          let glyph = arrangement.arrangedGlyphs[glyphIndex]
          width += glyph.glyphWrapWidth()
          if glyph.isWhitespace and glyph.rect.w > 0:
            inc spaces
            narrowestSpace = min(narrowestSpace, glyph.glyphWrapWidth())
        let target = boxWidth - style.lineIndent(info.first) - style.tailIndent
        if spaces > 0:
          extraPerSpace = (target - width) / spaces.float32
          # Never overlap glyphs when the measure is narrower than the words.
          extraPerSpace = max(extraPerSpace, -narrowestSpace)
    let height = arrangement.lineHeight(line)
    var lineX = 0.0'f32
    for glyphIndex in line:
      let
        oldGlyph = arrangement.arrangedGlyphs[glyphIndex]
        posOffset = oldGlyph.pos - oldGlyph.rect.xy
        stretched =
          extraPerSpace != 0 and glyphIndex in content and oldGlyph.isWhitespace and
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
      if style.align != paInherit:
        align = style.align
      if align == paJustify:
        if style.justifies(info):
          let content = arrangement.contentRange(line)
          if content.a <= content.b:
            bounds = arrangement.lineBounds(content)
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
