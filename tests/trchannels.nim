import std/[atomics, isolation, os, unittest]
import figdraw/common/rchannels

var destroyed: Atomic[int]

type Payload = object
  id: int

proc `=destroy`(payload: Payload) =
  if payload.id != 0:
    discard destroyed.fetchAdd(1)

type ReentrantPayload = object
  id: int

var
  reentrantChannel: RChan[ReentrantPayload]
  reentrantAlias: RChan[ReentrantPayload]
  reentrantReady: bool
  reentrantReceive: bool
  reentrantCallbackDone: bool

proc `=destroy`(payload: ReentrantPayload) =
  if reentrantReady and not reentrantCallbackDone:
    reentrantCallbackDone = true
    if reentrantReceive:
      var ignored: ReentrantPayload
      discard reentrantAlias.tryRecv(ignored)
    else:
      discard reentrantChannel.peek()

type BlockingPayload = object
  value: int

type RaisingPayload = object
  id: int

var raiseOnSink: bool

proc `=sink`(dest: var RaisingPayload, src: RaisingPayload) =
  if raiseOnSink:
    raise newException(ValueError, "test sink failure")
  dest.id = src.id

var
  blockingSinkStarted: Atomic[bool]
  allowBlockingSink: Atomic[bool]
  blockingSinkRaise: bool
  raceInitialDone: Atomic[bool]
  allowRaceRetry: Atomic[bool]
  raceResult: Atomic[bool]
  raceRetryResult: Atomic[bool]
  raceSource: Atomic[int]

proc `=sink`(dest: var BlockingPayload, src: BlockingPayload) =
  if blockingSinkRaise:
    raise newException(ValueError, "rollback sink failure")
  dest.value = src.value
  if not blockingSinkStarted.load(moAcquire):
    blockingSinkStarted.store(true, moRelease)
    while not allowBlockingSink.load(moAcquire):
      sleep(1)

var raceChannel: RChan[BlockingPayload]

proc tryTakeDuringPush() {.thread.} =
  {.cast(gcsafe).}:
    var source = isolate(BlockingPayload(value: 42))
    let succeeded = raceChannel.tryTake(source)
    raceResult.store(succeeded, moRelease)
    if not succeeded:
      var restored = extract(source)
      raceSource.store(restored.value, moRelease)
      source = isolate(move restored)
    raceInitialDone.store(true, moRelease)
    if not succeeded:
      while not allowRaceRetry.load(moAcquire):
        sleep(1)
      raceRetryResult.store(raceChannel.tryTake(source), moRelease)

proc tryTakeWithRaisingRollback() {.thread.} =
  {.cast(gcsafe).}:
    var source = isolate(BlockingPayload(value: 42))
    try:
      discard raceChannel.tryTake(source)
    except ValueError:
      raceRetryResult.store(true, moRelease)

const RaceWaitLimit = 5000

proc waitForFlag(flag: var Atomic[bool]): bool =
  for _ in 0 ..< RaceWaitLimit:
    if flag.load(moAcquire):
      return true
    sleep(1)

suite "RChan managed payload ownership":
  test "tryRecv destroys received payloads exactly once":
    const iterations = 100
    destroyed.store(0)
    block:
      let channel = newRChan[Payload](1)
      var value: Payload
      for id in 1 .. iterations:
        channel.send(isolate(Payload(id: id)))
        check channel.tryRecv(value)
        check value.id == id
    check destroyed.load() == iterations

  test "recv destroys received payloads exactly once":
    const iterations = 100
    destroyed.store(0)
    block:
      let channel = newRChan[Payload](1)
      for id in 1 .. iterations:
        channel.send(isolate(Payload(id: id)))
        let value = channel.recv()
        check value.id == id
    check destroyed.load() == iterations

  test "recv into a destination destroys the previous value":
    const iterations = 100
    destroyed.store(0)
    block:
      let channel = newRChan[Payload](1)
      var value: Payload
      for id in 1 .. iterations:
        channel.send(isolate(Payload(id: id)))
        channel.recv(value)
        check value.id == id
    check destroyed.load() == iterations

  test "push destroys overwritten payloads":
    destroyed.store(0)
    block:
      let channel = newRChan[Payload](1)
      channel.push(isolate(Payload(id: 1)))
      channel.push(isolate(Payload(id: 2)))
      check channel.recv().id == 2
    check destroyed.load() == 2

  test "the final shared owner destroys unread payloads":
    destroyed.store(0)
    block:
      var retained: RChan[Payload]
      block:
        let channel = newRChan[Payload](1)
        retained = channel
        channel.send(isolate(Payload(id: 1)))
      check destroyed.load() == 0
    check destroyed.load() == 1

  test "payload destruction can re-enter the channel":
    reentrantReady = false
    reentrantReceive = false
    reentrantCallbackDone = false
    block:
      let channel = newRChan[ReentrantPayload](1)
      reentrantChannel = channel
      reentrantReady = true
      channel.send(isolate(ReentrantPayload(id: 1)))
      var value: ReentrantPayload
      check channel.tryRecv(value)
    reentrantReady = false
    reset(reentrantChannel)

  test "final-owner cleanup detaches queued items before destruction":
    reentrantReady = true
    reentrantReceive = true
    reentrantCallbackDone = false
    block:
      let channel = newRChan[ReentrantPayload](1)
      copyMem(addr reentrantAlias, unsafeAddr channel, sizeof(reentrantAlias))
      channel.send(isolate(ReentrantPayload(id: 1)))
    wasMoved(reentrantAlias)
    reentrantReady = false
    reentrantReceive = false

  test "tryTake preserves its source when push wins the commit race":
    blockingSinkStarted.store(false)
    allowBlockingSink.store(false)
    raceInitialDone.store(false)
    allowRaceRetry.store(false)
    raceResult.store(true)
    raceRetryResult.store(false)
    raceSource.store(0)
    raceChannel = newRChan[BlockingPayload](1)

    var worker: Thread[void]
    createThread(worker, tryTakeDuringPush)
    let sinkStarted = waitForFlag(blockingSinkStarted)
    if sinkStarted:
      raceChannel.push(BlockingPayload(value: 99))
    allowBlockingSink.store(true, moRelease)
    let initialDone = waitForFlag(raceInitialDone)
    if initialDone and not raceResult.load(moAcquire):
      var queued: BlockingPayload
      check raceChannel.tryRecv(queued)
      check queued.value == 99
    allowRaceRetry.store(true, moRelease)
    joinThread(worker)

    check sinkStarted
    check initialDone
    if sinkStarted and initialDone:
      check not raceResult.load(moAcquire)
      check raceSource.load(moAcquire) == 42
      check raceRetryResult.load(moAcquire)
      var retried: BlockingPayload
      check raceChannel.tryRecv(retried)
      check retried.value == 42
    var leftover: BlockingPayload
    discard raceChannel.tryRecv(leftover)
    raceChannel = RChan[BlockingPayload]()

  test "raising ownership hooks do not strand channel capacity":
    let channel = newRChan[RaisingPayload](1)
    var source = isolate(RaisingPayload(id: 1))
    raiseOnSink = true
    expect ValueError:
      discard channel.tryTake(source)
    raiseOnSink = false

    check channel.peek() == 0
    channel.send(isolate(RaisingPayload(id: 2)))
    check channel.recv().id == 2

    channel.send(isolate(RaisingPayload(id: 3)))
    var destination = RaisingPayload(id: 0)
    raiseOnSink = true
    expect ValueError:
      channel.recv(destination)
    raiseOnSink = false

    check channel.peek() == 0
    channel.send(isolate(RaisingPayload(id: 4)))
    check channel.recv().id == 4

  test "raising rollback hooks still free the rejected item":
    let liveItemsBefore = rchanLiveItems.load(moAcquire)
    blockingSinkStarted.store(false)
    allowBlockingSink.store(false)
    blockingSinkRaise = false
    raceRetryResult.store(false)
    raceChannel = newRChan[BlockingPayload](1)

    var worker: Thread[void]
    createThread(worker, tryTakeWithRaisingRollback)
    let sinkStarted = waitForFlag(blockingSinkStarted)
    if sinkStarted:
      raceChannel.push(BlockingPayload(value: 99))
      blockingSinkRaise = true
    allowBlockingSink.store(true, moRelease)
    joinThread(worker)
    blockingSinkRaise = false

    check sinkStarted
    check raceRetryResult.load(moAcquire)
    var queued: BlockingPayload
    check raceChannel.tryRecv(queued)
    check queued.value == 99
    raceChannel = RChan[BlockingPayload]()
    check rchanLiveItems.load(moAcquire) == liveItemsBefore

when defined(linux):
  import std/strutils

  proc rssKb(): int64 =
    for line in lines("/proc/self/status"):
      if line.startsWith("VmRSS:"):
        let fields = line.splitWhitespace()
        if fields.len >= 2:
          return parseInt(fields[1]).int64
    raise newException(IOError, "unable to read VmRSS from /proc/self/status")

elif defined(macosx):
  type
    MachPort = uint32
    MachMsgTypeNumber = uint32
    TimeValue = object
      seconds: int32
      microseconds: int32

    MachTaskBasicInfo = object
      virtualSize: uint64
      residentSize: uint64
      residentSizeMax: uint64
      userTime: TimeValue
      systemTime: TimeValue
      policy: int32
      suspendCount: int32

  const machTaskBasicInfoFlavor = 20

  var machTaskSelf {.importc: "mach_task_self_", header: "<mach/mach_init.h>".}:
    MachPort

  proc taskInfo(
    task: MachPort,
    flavor: cint,
    taskInfoOut: ptr MachTaskBasicInfo,
    taskInfoOutCount: ptr MachMsgTypeNumber,
  ): cint {.importc: "task_info", header: "<mach/task.h>".}

  proc rssKb(): int64 =
    var info: MachTaskBasicInfo
    var count = MachMsgTypeNumber(sizeof(MachTaskBasicInfo) div sizeof(cuint))
    let status = taskInfo(machTaskSelf, machTaskBasicInfoFlavor, addr info, addr count)
    doAssert status == 0, "task_info failed with kern_return_t " & $status
    int64(info.residentSize div 1024)

when defined(linux) or defined(macosx):
  const
    RssSampleCount = 6
    RssIterationsPerSample = 64
    RssPayloadSize = 512 * 1024
    RssMaxGrowthKb = 64 * 1024

  proc median3(a, b, c: int64): int64 =
    a + b + c - min(a, min(b, c)) - max(a, max(b, c))

  proc newRssPayload(size: int): string =
    result = newString(size)
    var index = 0
    while index < size:
      result[index] = 'x'
      inc index, 4096
    result[^1] = 'x'

  proc drainChannel(iterations, payloadSize: int, useTryRecv: bool): bool =
    let channel = newRChan[string](1)
    var value: string
    for _ in 0 ..< iterations:
      channel.send(isolate(newRssPayload(payloadSize)))
      if useTryRecv:
        if not channel.tryRecv(value):
          return false
      else:
        channel.recv(value)
    true

  proc rchanRssGrowth(useTryRecv: bool): int64 =
    var samples: array[RssSampleCount, int64]
    for index in 0 ..< RssSampleCount:
      doAssert drainChannel(RssIterationsPerSample, RssPayloadSize, useTryRecv)
      samples[index] = rssKb()
    let early = median3(samples[0], samples[1], samples[2])
    let late = median3(samples[3], samples[4], samples[5])
    max(0'i64, late - early)

  suite "RChan managed payload RSS":
    test "tryRecv does not retain managed payloads":
      check rchanRssGrowth(useTryRecv = true) <= RssMaxGrowthKb

    test "recv does not retain managed payloads":
      check rchanRssGrowth(useTryRecv = false) <= RssMaxGrowthKb
