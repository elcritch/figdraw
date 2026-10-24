## Synchronous sdfy row rendering with an automatic internal Sigils worker pool.

import std/[locks, os]
import pkg/[chroma, pixie, vmath]
import pkg/sdfy/spans
const ThreadedSdfyEnabled* {.booldefine: "figdraw.threadedSdfy".} = true

type
  SdfyRaster* = object
    field*: RoundedBoxField
    paint*: SpanPaint
    effect*: SpanEffect
    clip*: SpanClip
    transform*: Mat3
    useSimd*: bool

  RasterBatch = object
    lock: Lock
    ready: Cond
    remaining: int
    errorLength: int
    error: array[512, char]

  RasterTile = object
    raster: SdfyRaster
    pixels, mask: ptr UncheckedArray[ColorRGBX]
    width, x0, x1, y0, y1: int
    batch: ptr RasterBatch

proc renderRows(tile: RasterTile) =
  for y in tile.y0 ..< tile.y1:
    let first = y * tile.width + tile.x0
    let last = first + tile.x1 - tile.x0 - 1
    let coordinates = initSpanCoordinates(
      vec2(tile.x0.float32 + 0.5'f32, y.float32 + 0.5'f32),
      transform = tile.raster.transform,
    )
    if tile.mask.isNil:
      drawRoundedBoxSpan(
        tile.pixels.toOpenArray(first, last),
        tile.raster.field,
        coordinates,
        tile.raster.paint,
        tile.raster.effect,
        tile.raster.clip,
        useSimd = tile.raster.useSimd,
      )
    else:
      drawRoundedBoxSpan(
        tile.pixels.toOpenArray(first, last),
        tile.raster.field,
        coordinates,
        tile.raster.paint,
        tile.raster.effect,
        tile.raster.clip,
        mask = tile.mask.toOpenArray(first, last),
        useSimd = tile.raster.useSimd,
      )

when ThreadedSdfyEnabled:
  import std/[cpuinfo, exitprocs]
  import pkg/sigils
  import pkg/sigils/[threadPool, threadProxies]

  type
    TileSource = ref object of AgentActor
    TileWorker = ref object of AgentActor

    RasterWorkers* = ref object
      pool: SigilThreadPoolPtr
      sources: seq[TileSource]
      proxies: seq[AgentProxy[TileWorker]]
      owner: int
      count: int
      threshold: int

  proc tileRequested(source: TileSource, tile: RasterTile) {.signal.}

  proc render(worker: TileWorker, tile: RasterTile) {.slot.} =
    try:
      renderRows(tile)
    except Exception as error:
      withLock tile.batch.lock:
        if tile.batch.errorLength == 0:
          tile.batch.errorLength = min(error.msg.len, tile.batch.error.len - 1)
          for i in 0 ..< tile.batch.errorLength:
            tile.batch.error[i] = error.msg[i]
          if tile.batch.errorLength == 0:
            tile.batch.error[0] = '?'
            tile.batch.errorLength = 1
    finally:
      withLock tile.batch.lock:
        dec tile.batch.remaining
        if tile.batch.remaining == 0:
          tile.batch.ready.signal()

  # Runtime pools are private, lazy, and shared by contexts with the same count.
  # Keep the cache alive through C exit callbacks, as std/exitprocs does itself.
  var poolLock: Lock
  var cachedPools {.cursor.}: seq[SigilThreadPoolPtr]
  poolLock.initLock()

  proc shutdownPools() {.noconv.} =
    withLock poolLock:
      for pool in cachedPools:
        pool.stop()
      for pool in cachedPools:
        pool.join()

  addExitProc(shutdownPools)

  proc sharedPool(count: int): SigilThreadPoolPtr {.gcsafe.} =
    # The cache stores only scheduler pointers; every access is lock protected.
    {.cast(gcsafe).}:
      withLock poolLock:
        for pool in cachedPools:
          if pool.workerCount == count:
            return pool
        result = newSigilThreadPool(workers = count)
        result.start()
        cachedPools.add(result)

  proc initRasterWorkers*(
      workers: Natural = 0, threshold: Positive = 262_144
  ): RasterWorkers =
    let count =
      if workers == 0:
        min(4, countProcessors())
      else:
        workers.int
    if count > 1:
      result = RasterWorkers(owner: getThreadId(), count: count, threshold: threshold)

  proc prepare(workers: RasterWorkers) =
    if workers.owner != getThreadId():
      raise newException(
        ValueError, "Software worker dispatch belongs to its creating thread"
      )
    if workers.pool.isNil:
      workers.pool = sharedPool(workers.count)
    if workers.proxies.len == 0:
      for i in 0 ..< workers.count:
        let source = TileSource.new()
        var worker = TileWorker.new()
        let proxy = worker.moveToThread(workers.pool)
        connectThreaded(source, tileRequested, proxy, render)
        workers.sources.add(source)
        workers.proxies.add(proxy)

  proc renderParallel(workers: RasterWorkers, tile: RasterTile) =
    workers.prepare()
    let count = min(workers.proxies.len, tile.y1 - tile.y0)
    var batch = RasterBatch(remaining: count)
    batch.lock.initLock()
    batch.ready.initCond()
    var submitted = 0
    try:
      try:
        for i in 0 ..< count:
          var part = tile
          part.y0 = tile.y0 + (tile.y1 - tile.y0) * i div count
          part.y1 = tile.y0 + (tile.y1 - tile.y0) * (i + 1) div count
          part.batch = batch.addr
          emit workers.sources[i].tileRequested(part)
          inc submitted
      finally:
        # A failed enqueue must still wait for every successfully submitted job.
        withLock batch.lock:
          batch.remaining -= count - submitted
          while batch.remaining > 0:
            batch.ready.wait(batch.lock)
      if batch.errorLength > 0:
        var message = newString(batch.errorLength)
        for i in 0 ..< message.len:
          message[i] = batch.error[i]
        raise newException(ValueError, "Software worker failed: " & message)
    finally:
      batch.ready.deinitCond()
      batch.lock.deinitLock()

else:
  type RasterWorkers* = ref object

  proc initRasterWorkers*(
      workers: Natural = 0, threshold: Positive = 262_144
  ): RasterWorkers =
    nil

proc renderSdfy*(
    workers: RasterWorkers, raster: SdfyRaster, image, mask: Image, x0, y0, x1, y1: int
) =
  ## Image owners stay alive here until all jobs finish. Workers receive only
  ## value parameters and borrowed buffer pointers. Tiles write disjoint rows;
  ## the parent mask is read-only. Each draw is a barrier before the next draw.
  if x0 >= x1 or y0 >= y1:
    return
  if image.isNil or x0 < 0 or y0 < 0 or x1 > image.width or y1 > image.height:
    raise newException(ValueError, "Software raster bounds exceed the destination")
  if not mask.isNil and (mask.width != image.width or mask.height != image.height):
    raise
      newException(ValueError, "Software mask dimensions must match the destination")
  var tile = RasterTile(
    raster: raster,
    width: image.width,
    pixels: cast[ptr UncheckedArray[ColorRGBX]](image.data[0].addr),
    x0: x0,
    x1: x1,
    y0: y0,
    y1: y1,
  )
  if not mask.isNil:
    tile.mask = cast[ptr UncheckedArray[ColorRGBX]](mask.data[0].addr)
  when ThreadedSdfyEnabled:
    if not workers.isNil and (x1 - x0) * (y1 - y0) >= workers.threshold and y1 - y0 > 1:
      workers.renderParallel(tile)
      return
  renderRows(tile)
