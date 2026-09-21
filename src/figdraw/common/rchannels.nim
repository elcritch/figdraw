#
#
#                                    Nim's Runtime Library
#        (c) Copyright 2021 Andreas Prell, Mamy André-Ratsimbazafy & Nim Contributors
#
#    See the file "copying.txt", included in this
#    distribution, for details about the copyright.
#
# This Channel implementation is a shared memory, fixed-size, concurrent queue using
# a circular buffer for data. Based on channels implementation[1]_ by
# Mamy André-Ratsimbazafy (@mratsim), which is a C to Nim translation of the
# original[2]_ by Andreas Prell (@aprell)
#
# .. [1] https://github.com/mratsim/weave/blob/5696d94e6358711e840f8c0b7c684fcc5cbd4472/unused/channels/channels_legacy.nim
# .. [2] https://github.com/aprell/tasking-2.0/blob/master/src/channel_shm/channel.c

## This module works only with one of `--mm:arc` / `--mm:atomicArc` / `--mm:orc`
## compilation flags.
##
## .. warning:: This module is experimental and its interface may change.
##
## This module implements multi-producer multi-consumer channels - a concurrency
## primitive with a high-level interface intended for communication and
## synchronization between threads. It allows sending and receiving typed, isolated
## data, enabling safe and efficient concurrency.
##
## The `RChan` type represents a generic fixed-size channel object that internally manages
## the underlying resources and synchronization. It has to be initialized using
## the `newRChan` proc. Sending and receiving operations are provided by the
## blocking `send` and `recv` procs, and non-blocking `trySend` and `tryRecv`
## procs. For ring buffer behavior, use the `push` proc rather than `send`.
## Send operations add messages to the channel, receiving operations remove them,
## while `push` adds a message or overwrites the oldest message if the channel is full.
##
##
## See also:
## * [std/isolation](https://nim-lang.org/docs/isolation.html)
##
## The following is a simple example of two different ways to use channels:
## blocking and non-blocking.

runnableExamples("--threads:on --gc:orc"):
  import std/os

  # In this example a channel is declared at module scope.
  # Channels are generic, and they include support for passing objects between
  # threads.
  # Note that isolated data passed through channels is moved around.
  var RChan = newRChan[string]()

  block example_blocking:
    # This proc will be run in another thread.
    proc basicWorker() =
      RChan.send("Hello World!")

    # Launch the worker.
    var worker: Thread[void]
    createThread(worker, basicWorker)

    # Block until the message arrives, then print it out.
    var dest = ""
    dest = RChan.recv()
    assert dest == "Hello World!"

    # Wait for the thread to exit before moving on to the next example.
    worker.joinThread()

  block example_non_blocking:
    # This is another proc to run in a background thread. This proc takes a while
    # to send the message since it first sleeps for some time.
    proc slowWorker(delay: Natural) =
      # `delay` is a period in milliseconds
      sleep(delay)
      RChan.send("Another message")

    # Launch the worker with a delay set to 2 seconds (2000 ms).
    var worker: Thread[Natural]
    createThread(worker, slowWorker, 2000)

    # This time, use a non-blocking approach with tryRecv.
    # Since the main thread is not blocked, it could be used to perform other
    # useful work while it waits for data to arrive on the channel.
    var messages: seq[string]
    while true:
      var msg = ""
      if RChan.tryRecv(msg):
        messages.add msg # "Another message"
        break
      messages.add "Pretend I'm doing useful work..."
      # For this example, sleep in order not to flood the sequence with too many
      # "pretend" messages.
      sleep(400)

    # Wait for the second thread to exit before cleaning up the channel.
    worker.joinThread()

    # Thread exits right after receiving the message
    assert messages[^1] == "Another message"
    # At least one non-successful attempt to receive the message had to occur.
    assert messages.len >= 2

  block example_non_blocking_overwrite:
    var chanRingBuffer = newRChan[string](elements = 1)
    chanRingBuffer.push("Hello")
    chanRingBuffer.push("World")
    var msg = ""
    assert chanRingBuffer.tryRecv(msg)
    assert msg == "World"

when not (defined(gcArc) or defined(gcOrc) or defined(gcAtomicArc) or defined(nimdoc)):
  {.
    error:
      "This module requires one of --mm:arc / --mm:atomicArc / --mm:orc compilation flags"
  .}

import std/[atomics, deques, isolation, locks]

# Channel
# ------------------------------------------------------------------------------

type
  RChanItemData[T] = object
    value: T

  RChanItem[T] = ptr RChanItemData[T]

  RChanData[T] = object
    lock: Lock
    spaceAvailableCV, dataAvailableCV: Cond
    items: Deque[RChanItem[T]]
    capacity: int
    pendingSends: int
    atomicCounter: Atomic[int]

  RChan*[T] = object ## Typed channel
    d: ptr RChanData[T]

when defined(figdrawRChanTests):
  var rchanLiveItems*: Atomic[int]

# The old implementation stored values in an untyped byte buffer and used
# copyMem to move them. That is not valid for managed values: the compiler never
# sees the slot's references, so overwriting or receiving a value cannot destroy
# the old owner. Keep the queue's entries as pointers to individually owned,
# typed values. Pointer operations are safe under the lock; each pointed-to
# value is constructed and destroyed outside the lock so user destructors can
# call back into the channel.

proc allocItem[T](value: var Isolated[T]): RChanItem[T] =
  result = cast[RChanItem[T]](allocShared0(sizeof(RChanItemData[T])))
  when defined(figdrawRChanTests):
    discard rchanLiveItems.fetchAdd(1, moRelaxed)
  try:
    result[].value = extract(value)
  except:
    try:
      `=destroy`(result[].value)
    finally:
      deallocShared(result)
      when defined(figdrawRChanTests):
        discard rchanLiveItems.fetchSub(1, moRelaxed)
    raise

proc freeItem[T](item: RChanItem[T]) =
  if item.isNil:
    return
  try:
    `=destroy`(item[].value)
  finally:
    deallocShared(item)
    when defined(figdrawRChanTests):
      discard rchanLiveItems.fetchSub(1, moRelaxed)

proc allocChannel[T](n: Positive): ptr RChanData[T] =
  result = cast[ptr RChanData[T]](allocShared0(sizeof(RChanData[T])))
  result[].items = initDeque[RChanItem[T]]()
  result[].capacity = n
  result[].atomicCounter.store(1, moRelaxed)
  initLock(result[].lock)
  initCond(result[].spaceAvailableCV)
  initCond(result[].dataAvailableCV)

proc freeChannel[T](channel: ptr RChanData[T]) =
  if channel.isNil:
    return

  # RChanData lives in shared raw storage, so its managed queue field and every
  # pointed-to managed value need explicit destruction before the allocation is
  # released. No channel lock is held while payload destructors run.
  # Detach the queue first: a payload destructor is allowed to re-enter the
  # channel, and must not be able to receive an item that teardown is already
  # destroying.
  var items = channel[].items
  channel[].items = initDeque[RChanItem[T]]()
  for item in items.items:
    freeItem(item)
  deinitCond(channel[].spaceAvailableCV)
  deinitCond(channel[].dataAvailableCV)
  deinitLock(channel[].lock)
  deallocShared(channel)

proc channelSend[T](
    channel: ptr RChanData[T],
    value: var Isolated[T],
    blocking: static bool,
    overwrite: static bool,
): bool =
  assert not channel.isNil

  when overwrite:
    let overwriteItem = allocItem(value)
    var dropped: RChanItem[T]
    var overwriteEnqueued = false
    try:
      acquire(channel[].lock)
      try:
        if channel[].items.len == channel[].capacity:
          # Move the old owner out while holding the lock, but free its value
          # after the lock is released. User destructors may call back into the
          # channel.
          dropped = channel[].items.popFirst()
        channel[].items.addLast(overwriteItem)
        overwriteEnqueued = true
        signal(channel[].dataAvailableCV)
      finally:
        release(channel[].lock)
    except:
      if not overwriteEnqueued:
        freeItem(overwriteItem)
      freeItem(dropped)
      raise
    freeItem(dropped)
    return true
  else:
    acquire(channel[].lock)
    if blocking:
      while channel[].items.len + channel[].pendingSends >= channel[].capacity:
        wait(channel[].spaceAvailableCV, channel[].lock)
    else:
      if channel[].items.len + channel[].pendingSends >= channel[].capacity:
        release(channel[].lock)
        return false
    inc channel[].pendingSends

    release(channel[].lock)
    var item: RChanItem[T]
    try:
      item = allocItem(value)
    except:
      acquire(channel[].lock)
      dec channel[].pendingSends
      signal(channel[].spaceAvailableCV)
      release(channel[].lock)
      raise

    var commitRejected = false
    var sendEnqueued = false
    try:
      acquire(channel[].lock)
      try:
        dec channel[].pendingSends
        if not blocking:
          if channel[].items.len == channel[].capacity:
            commitRejected = true
        else:
          while channel[].items.len == channel[].capacity:
            wait(channel[].spaceAvailableCV, channel[].lock)
        if not commitRejected:
          channel[].items.addLast(item)
          sendEnqueued = true
          signal(channel[].dataAvailableCV)
      finally:
        release(channel[].lock)
    except:
      if not sendEnqueued:
        freeItem(item)
      raise

    if commitRejected:
      try:
        value = unsafeIsolate(move item[].value)
      finally:
        freeItem(item)
      return false
    result = true

proc channelReceive[T](
    channel: ptr RChanData[T], value: var T, blocking: static bool
): bool =
  assert not channel.isNil

  var received: RChanItem[T]
  acquire(channel[].lock)
  when blocking:
    while channel[].items.len == 0:
      wait(channel[].dataAvailableCV, channel[].lock)
  else:
    if channel[].items.len == 0:
      release(channel[].lock)
      return false

  # Move the owner out while holding the lock, but assign it to the caller's
  # destination after unlocking. That assignment destroys any value already
  # owned by the destination; T's destructor could call back into the channel.
  received = channel[].items.popFirst()
  signal(channel[].spaceAvailableCV)
  release(channel[].lock)
  try:
    value = move received[].value
  finally:
    freeItem(received)
  result = true

# Public API
# ------------------------------------------------------------------------------

template frees(c) =
  if c.d != nil:
    # this `fetchSub` returns current val then subs
    # fetchSub returns the count before decrementing, so one means this is the
    # final owner.
    if c.d.atomicCounter.fetchSub(1, moAcquireRelease) == 1:
      freeChannel(c.d)

when defined(nimAllowNonVarDestructor):
  proc `=destroy`*[T](c: RChan[T]) =
    frees(c)

else:
  proc `=destroy`*[T](c: var RChan[T]) =
    frees(c)

proc `=wasMoved`*[T](x: var RChan[T]) =
  x.d = nil

proc `=dup`*[T](src: RChan[T]): RChan[T] =
  if src.d != nil:
    discard fetchAdd(src.d.atomicCounter, 1, moRelaxed)
  result.d = src.d

proc `=copy`*[T](dest: var RChan[T], src: RChan[T]) =
  ## Shares `Channel` by reference counting.
  if src.d != nil:
    discard fetchAdd(src.d.atomicCounter, 1, moRelaxed)
  `=destroy`(dest)
  dest.d = src.d

proc trySend*[T](c: RChan[T], src: sink Isolated[T]): bool {.inline.} =
  ## Tries to send the message `src` to the channel `c`.
  ##
  ## The memory of `src` will be moved if possible.
  ## Doesn't block waiting for space in the channel to become available.
  ## Instead returns after an attempt to send a message was made.
  ##
  ## .. warning:: In high-concurrency situations, consider using an exponential
  ##    backoff strategy to reduce contention and improve the success rate of
  ##    operations.
  ##
  ## Returns `false` if the message was not sent because the number of pending
  ## messages in the channel exceeded its capacity.
  result = channelSend(c.d, src, false, false)
  if result:
    wasMoved(src)

template trySend*[T](c: RChan[T], src: T): bool =
  ## Helper template for `trySend <#trySend,RChan[T],sinkIsolated[T]>`_.
  ##
  ## .. warning:: For repeated sends of the same value, consider using the
  ##    `tryTake <#tryTake,RChan[T],Isolated[T]>`_ proc with a pre-isolated
  ##    value to avoid unnecessary copying.
  mixin isolate
  trySend(c, isolate(src))

proc tryTake*[T](c: RChan[T], src: var Isolated[T]): bool {.inline.} =
  ## Tries to send the message `src` to the channel `c`.
  ##
  ## The memory of `src` is moved directly. Be careful not to reuse `src` afterwards.
  ## This proc is suitable when `src` cannot be copied.
  ##
  ## Doesn't block waiting for space in the channel to become available.
  ## Instead returns after an attempt to send a message was made.
  ##
  ## .. warning:: In high-concurrency situations, consider using an exponential
  ##    backoff strategy to reduce contention and improve the success rate of
  ##    operations.
  ##
  ## Returns `false` if the message was not sent because the number of pending
  ## messages in the channel exceeded its capacity.
  result = channelSend(c.d, src, false, false)
  if result:
    wasMoved(src)

proc tryRecv*[T](c: RChan[T], dst: var T): bool {.inline.} =
  ## Tries to receive a message from the channel `c` and fill `dst` with its value.
  ##
  ## Doesn't block waiting for messages in the channel to become available.
  ## Instead returns after an attempt to receive a message was made.
  ##
  ## .. warning:: In high-concurrency situations, consider using an exponential
  ##    backoff strategy to reduce contention and improve the success rate of
  ##    operations.
  ##
  ## Returns `false` and does not change `dst` if no message was received.
  channelReceive(c.d, dst, false)

proc send*[T](c: RChan[T], src: sink Isolated[T]) {.inline.} =
  ## Sends the message `src` to the channel `c`.
  ## This blocks the sending thread until `src` was successfully sent.
  ##
  ## The memory of `src` is moved, not copied.
  ##
  ## If the channel is already full with messages this will block the thread until
  ## messages from the channel are removed.
  when defined(gcOrc) and defined(nimSafeOrcSend):
    GC_runOrc()
  discard channelSend(c.d, src, true, false)
  wasMoved(src)

template send*[T](c: RChan[T], src: T) =
  ## Helper template for `send`.
  mixin isolate
  send(c, isolate(src))

proc push*[T](c: RChan[T], src: sink Isolated[T]) {.inline.} =
  ## Pushes the message `src` to the channel `c`.
  ## This is a non-blocking operation that overwrites the oldest message if the channel is full.
  ##
  ## The memory of `src` is moved, not copied.
  when defined(gcOrc) and defined(nimSafeOrcSend):
    GC_runOrc()
  discard channelSend(c.d, src, false, true)
  wasMoved(src)

template push*[T](c: RChan[T], src: T) =
  ## Helper template for `push`.
  mixin isolate
  push(c, isolate(src))

proc recv*[T](c: RChan[T], dst: var T) {.inline.} =
  ## Receives a message from the channel `c` and fill `dst` with its value.
  ##
  ## This blocks the receiving thread until a message was successfully received.
  ##
  ## If the channel does not contain any messages this will block the thread until
  ## a message get sent to the channel.
  discard channelReceive(c.d, dst, true)

proc recv*[T](c: RChan[T]): T {.inline.} =
  ## Receives a message from the channel.
  ## A version of `recv`_ that returns the message.
  discard channelReceive(c.d, result, true)

proc recvIso*[T](c: RChan[T]): Isolated[T] {.inline.} =
  ## Receives a message from the channel.
  ## A version of `recv`_ that returns the message and isolates it.
  var value: T
  discard channelReceive(c.d, value, true)
  result = unsafeIsolate(move value)

proc peek*[T](c: RChan[T]): int {.inline.} =
  ## Returns an estimation of the current number of messages held by the channel.
  acquire(c.d[].lock)
  result = c.d[].items.len
  release(c.d[].lock)

proc newRChan*[T](elements: Positive = 30): RChan[T] =
  ## An initialization procedure, necessary for acquiring resources and
  ## initializing internal state of the channel.
  ##
  ## `elements` is the capacity of the channel and thus how many messages it can hold
  ## before it refuses to accept any further messages.
  result = RChan[T](d: allocChannel[T](elements))
