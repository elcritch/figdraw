import std/[algorithm, math, monotimes, strformat, times]

import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

const BenchRows {.intdefine: "figdraw.bench.rows".} = 180
const BenchCols {.intdefine: "figdraw.bench.cols".} = 6
const WarmupFrames {.intdefine: "figdraw.bench.warmup".} = 20
const TimedFrames {.intdefine: "figdraw.bench.frames".} = 120
const WindowW {.intdefine: "figdraw.bench.windowW".} = 1200
const WindowH {.intdefine: "figdraw.bench.windowH".} = 800

static:
  doAssert BenchRows > 0, "figdraw.bench.rows must be positive"
  doAssert BenchCols > 0, "figdraw.bench.cols must be positive"
  doAssert WarmupFrames >= 0, "figdraw.bench.warmup must be non-negative"
  doAssert TimedFrames > 0, "figdraw.bench.frames must be positive"
  doAssert WindowW > 0 and WindowH > 0, "benchmark window size must be positive"
  doAssert 2 + BenchRows * BenchCols * 4 <= high(int16).int,
    "benchmark render tree exceeds FigIdx int16 capacity"

type
  BenchKind = enum
    bkSubClip
    bkRectMask

  BenchStats = object
    count: int
    minMs: float64
    avgMs: float64
    p50Ms: float64
    p95Ms: float64
    maxMs: float64

proc elapsedMs(started: MonoTime): float64 =
  (getMonoTime() - started).inNanoseconds.float64 / 1_000_000.0

func percentile(sortedSamples: seq[float64], p: float64): float64 =
  if sortedSamples.len == 0:
    return 0.0

  let rawIndex = int(round((sortedSamples.len - 1).float64 * p))
  let idx = min(max(rawIndex, 0), sortedSamples.len - 1)
  sortedSamples[idx]

proc summarize(samples: seq[float64]): BenchStats =
  if samples.len == 0:
    return BenchStats()

  var sortedSamples = samples
  sortedSamples.sort()

  var total = 0.0
  for sample in samples:
    total += sample

  BenchStats(
    count: samples.len,
    minMs: sortedSamples[0],
    avgMs: total / samples.len.float64,
    p50Ms: percentile(sortedSamples, 0.50),
    p95Ms: percentile(sortedSamples, 0.95),
    maxMs: sortedSamples[^1],
  )

proc addRect(
    list: var RenderList,
    parentIdx: FigIdx,
    rectBox: Rect,
    color: ColorRGBA,
    flags: set[FigFlags] = {},
    corners: uint16 = 0'u16,
): FigIdx =
  list.addChild(
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
      flags: flags,
    ),
  )

proc addRootRect(
    list: var RenderList,
    rectBox: Rect,
    color: ColorRGBA,
    flags: set[FigFlags] = {},
    corners: uint16 = 0'u16,
): FigIdx =
  list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
      flags: flags,
    )
  )

proc addCellContent(
    list: var RenderList, cellIdx: FigIdx, cellRect: Rect, row, col: int
) =
  let
    tone = uint8(42 + (row * 7 + col * 17) mod 72)
    accent = rgba(36'u8, uint8(120 + (row * 5) mod 80), 235'u8, 255'u8)
    spill = rgba(tone, uint8(170 - (col * 11) mod 70), 220'u8, 255'u8)
    muted = rgba(uint8(190 + (row + col) mod 30), 210'u8, 220'u8, 255'u8)

  discard list.addRect(
    cellIdx,
    rect(cellRect.x - 12.0'f32, cellRect.y + 4.0'f32, cellRect.w + 24.0'f32, 5.0'f32),
    accent,
    corners = 2'u16,
  )
  discard list.addRect(
    cellIdx,
    rect(
      cellRect.x + cellRect.w * 0.38'f32,
      cellRect.y - 5.0'f32,
      cellRect.w * 0.74'f32,
      cellRect.h + 10.0'f32,
    ),
    spill,
    corners = 3'u16,
  )
  discard list.addRect(
    cellIdx,
    rect(
      cellRect.x + 7.0'f32,
      cellRect.y + cellRect.h - 7.0'f32,
      cellRect.w - 14.0'f32,
      8.0'f32,
    ),
    muted,
    corners = 2'u16,
  )

proc makeTableRenderTree(kind: BenchKind, w, h: float32): Renders =
  let
    bgColor = rgba(248, 249, 251, 255)
    viewportColor = rgba(232, 235, 240, 255)
    cellBase = rgba(255, 255, 255, 255)
    cellAlt = rgba(242, 246, 250, 255)
    margin = 22.0'f32
    gap = 4.0'f32
    viewport = rect(margin, margin, w - margin * 2.0'f32, h - margin * 2.0'f32)
    cellH = 22.0'f32
    cellW = (viewport.w - gap * (BenchCols + 1).float32) / BenchCols.float32
    scrollY = 37.0'f32

  var list = RenderList()
  discard list.addRootRect(rect(0.0'f32, 0.0'f32, w, h), bgColor)

  let viewportIdx =
    list.addRootRect(viewport, viewportColor, flags = {NfClipContent}, corners = 10'u16)

  for row in 0 ..< BenchRows:
    let y = viewport.y + gap + row.float32 * (cellH + gap) - scrollY
    for col in 0 ..< BenchCols:
      let
        x = viewport.x + gap + col.float32 * (cellW + gap)
        cellRect = rect(x, y, cellW, cellH)
        cellFlags =
          case kind
          of bkSubClip:
            {NfClipContent}
          of bkRectMask:
            {NfRectMaskContent}
        cellColor = if (row + col) mod 2 == 0: cellBase else: cellAlt

      let cellIdx = list.addRect(viewportIdx, cellRect, cellColor, cellFlags, 4'u16)
      list.addCellContent(cellIdx, cellRect, row, col)

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc drainGpu[BackendState](renderer: FigRenderer[BackendState]) =
  try:
    discard renderer.takeScreenshot(rect(0, 0, 1, 1), readFront = false)
  except CatchableError:
    discard

proc renderOneFrame[BackendState](
    renderer: FigRenderer[BackendState], renders: var Renders, frameSize: Vec2
) =
  renderer.beginFrame()
  renderer.renderFrame(renders, frameSize)
  renderer.endFrame()

proc warmup[BackendState](
    renderer: FigRenderer[BackendState], renders: var Renders, frameSize: Vec2
) =
  for _ in 0 ..< WarmupFrames:
    pollEvents()
    renderer.renderOneFrame(renders, frameSize)
  renderer.drainGpu()

proc benchmarkCase[BackendState](
    renderer: FigRenderer[BackendState],
    label: string,
    renders: var Renders,
    frameSize: Vec2,
): BenchStats =
  renderer.warmup(renders, frameSize)

  var samples = newSeqOfCap[float64](TimedFrames)
  for _ in 0 ..< TimedFrames:
    pollEvents()
    let started = getMonoTime()
    renderer.renderOneFrame(renders, frameSize)
    samples.add elapsedMs(started)

  renderer.drainGpu()
  result = summarize(samples)

  echo fmt"{label:<22} {result.avgMs:>9.3f} {result.p50Ms:>9.3f} " &
    fmt"{result.p95Ms:>9.3f} {result.minMs:>9.3f} {result.maxMs:>9.3f} " &
    fmt"{1000.0 / result.avgMs:>9.1f}"

when isMainModule:
  when defined(emscripten):
    echo "windy_clip_mask_benchmark is native-only."
  else:
    let
      title = windyWindowTitle("Clip vs Rect Mask Benchmark")
      size = ivec2(WindowW.int32, WindowH.int32)
      window = newWindyWindow(size = size, fullscreen = false, title = title)

    setFigUiScale window.contentScale()
    if size != size.scaled():
      window.size = size.scaled()

    let renderer = newFigRenderer(atlasSize = 512, backendState = WindyRenderBackend())
    renderer.setupBackend(window)

    try:
      pollEvents()
      let frameSize = window.logicalSize()
      var subClipRenders = makeTableRenderTree(bkSubClip, frameSize.x, frameSize.y)
      var rectMaskRenders = makeTableRenderTree(bkRectMask, frameSize.x, frameSize.y)
      let nodeCount = subClipRenders.layers[0.ZLevel].nodes.len

      echo "FigDraw clip/mask benchmark"
      echo "backend: ", renderer.backendName()
      echo "window: ", frameSize.x.int, "x", frameSize.y.int
      echo "cells: ",
        BenchRows * BenchCols, " (", BenchRows, " rows x ", BenchCols, " cols)"
      echo "nodes: ", nodeCount
      echo "warmup frames: ", WarmupFrames, " | timed frames: ", TimedFrames
      if renderer.backendKind() == rbVulkan:
        echo "note: this backend uses fallback mask-texture behavior for NfRectMaskContent."
      echo ""
      let
        caseHeader = "case"
        avgHeader = "avg ms"
        p50Header = "p50 ms"
        p95Header = "p95 ms"
        minHeader = "min ms"
        maxHeader = "max ms"
        fpsHeader = "fps"
      echo fmt"{caseHeader:<22} {avgHeader:>9} {p50Header:>9} " &
        fmt"{p95Header:>9} {minHeader:>9} {maxHeader:>9} {fpsHeader:>9}"

      let subClipStats =
        renderer.benchmarkCase("clip + sub-clip", subClipRenders, frameSize)
      let rectMaskStats =
        renderer.benchmarkCase("clip + rect-mask", rectMaskRenders, frameSize)

      echo ""
      echo fmt"rect-mask speedup vs sub-clip: {subClipStats.avgMs / rectMaskStats.avgMs:.2f}x"
    finally:
      window.close()
