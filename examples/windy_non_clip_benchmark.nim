import std/[algorithm, math, monotimes, strformat, times]

const Windowed {.booldefine: "figdraw.bench.windowed".} = false

when Windowed:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

const BenchRows {.intdefine: "figdraw.bench.rows".} = 180
const BenchCols {.intdefine: "figdraw.bench.cols".} = 10
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
  doAssert 1 + BenchRows * BenchCols <= high(int16).int,
    "benchmark render tree exceeds FigIdx int16 capacity"

type BenchStats = object
  count: int
  minMs: float64
  avgMs: float64
  p50Ms: float64
  p95Ms: float64
  maxMs: float64

func elapsedMs(started: MonoTime): float64 =
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

proc addRootRect(
    list: var RenderList, rectBox: Rect, color: ColorRGBA, corners: uint16 = 0'u16
) =
  discard list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
    )
  )

proc makeNonClipRenderTree(w, h: float32): Renders =
  let
    margin = 18.0'f32
    gap = 5.0'f32
    cellW = (w - margin * 2.0'f32 - gap * (BenchCols - 1).float32) / BenchCols.float32
    cellH = 18.0'f32

  var list = RenderList()
  list.addRootRect(rect(0.0'f32, 0.0'f32, w, h), rgba(248, 249, 251, 255))

  for row in 0 ..< BenchRows:
    let y = margin + row.float32 * (cellH + gap)
    for col in 0 ..< BenchCols:
      let
        x = margin + col.float32 * (cellW + gap)
        shade = uint8(220 + (row * 3 + col * 7) mod 35)
        accent = uint8(80 + (row * 11 + col * 13) mod 90)
      list.addRootRect(
        rect(x, y, cellW, cellH),
        rgba(shade, uint8(245 - (col mod 5) * 5), accent, 255),
        corners = 4,
      )

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
  when Windowed:
    renderer.beginFrame()
  renderer.renderFrame(renders, frameSize)
  when Windowed:
    renderer.endFrame()

proc warmup[BackendState](
    renderer: FigRenderer[BackendState], renders: var Renders, frameSize: Vec2
) =
  for _ in 0 ..< WarmupFrames:
    when Windowed:
      pollEvents()
    renderer.renderOneFrame(renders, frameSize)
  renderer.drainGpu()

proc benchmarkCase[BackendState](
    renderer: FigRenderer[BackendState],
    label: string,
    renders: var Renders,
    frameSize: Vec2,
    syncReadback = false,
): BenchStats =
  renderer.warmup(renders, frameSize)

  var samples = newSeqOfCap[float64](TimedFrames)
  for _ in 0 ..< TimedFrames:
    when Windowed:
      pollEvents()
    let started = getMonoTime()
    renderer.renderOneFrame(renders, frameSize)
    if syncReadback:
      renderer.drainGpu()
    samples.add elapsedMs(started)

  if not syncReadback:
    renderer.drainGpu()
  result = summarize(samples)

  echo fmt"{label:<22} {result.avgMs:>9.3f} {result.p50Ms:>9.3f} " &
    fmt"{result.p95Ms:>9.3f} {result.minMs:>9.3f} {result.maxMs:>9.3f} " &
    fmt"{1000.0 / result.avgMs:>9.1f}"

proc runBenchmark[BackendState](renderer: FigRenderer[BackendState], frameSize: Vec2) =
  var renders = makeNonClipRenderTree(frameSize.x, frameSize.y)
  let nodeCount = renders.layers[0.ZLevel].nodes.len

  echo "FigDraw non-clip benchmark"
  echo "backend: ", renderer.backendName()
  when Windowed:
    echo "mode: windowed"
  else:
    echo "mode: offscreen"
  echo "frame: ", frameSize.x.int, "x", frameSize.y.int
  echo "cells: ",
    BenchRows * BenchCols, " (", BenchRows, " rows x ", BenchCols, " cols)"
  echo "nodes: ", nodeCount
  echo "warmup frames: ", WarmupFrames, " | timed frames: ", TimedFrames
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

  discard renderer.benchmarkCase("async submit", renders, frameSize)
  discard
    renderer.benchmarkCase("sync readback", renders, frameSize, syncReadback = true)

when isMainModule:
  when defined(emscripten):
    echo "windy_non_clip_benchmark is native-only."
  else:
    when Windowed:
      let
        title = windyWindowTitle("Non-Clip Benchmark")
        size = ivec2(WindowW.int32, WindowH.int32)
        window = newWindyWindow(size = size, fullscreen = false, title = title)

      setFigUiScale window.contentScale()
      if size != size.scaled():
        window.size = size.scaled()

      let renderer =
        newFigRenderer(atlasSize = 512, backendState = WindyRenderBackend())
      renderer.setupBackend(window)

      try:
        pollEvents()
        renderer.runBenchmark(window.logicalSize())
      finally:
        window.close()
    else:
      let
        renderer = newFigRenderer(atlasSize = 512)
        frameSize = vec2(WindowW.float32, WindowH.float32)
      renderer.runBenchmark(frameSize)
