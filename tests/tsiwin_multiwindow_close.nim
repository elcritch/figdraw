import std/unittest

import figdraw/windowing/siwinshim

const TickLimit = 1200
const CloseAtTick = 60
const RequiredOtherTicks = 20

type CloseStats = tuple[otherTicksAfterFirstClose: int, firstObservedClosed: bool]

proc runCloseDirection(closeLeftFirst: bool): CloseStats =
  let win1 = newSiwinWindow(size = ivec2(320, 220), title = "figdraw test left")
  let win2 = newSiwinWindow(size = ivec2(320, 220), title = "figdraw test right")

  var
    ticks1 = 0
    ticks2 = 0
    closeIssued = false
    firstObservedClosed = false
    otherTicksAfterFirstClose = 0

  proc forceCloseBoth() =
    if win1.opened:
      close(win1)
    if win2.opened:
      close(win2)

  let win1Events = WindowEventsHandler(
    onTick: proc(e: TickEvent) =
      inc ticks1
      if closeLeftFirst:
        if not closeIssued and ticks1 >= CloseAtTick:
          closeIssued = true
          close(win1)
      else:
        if not win2.opened:
          firstObservedClosed = true
          inc otherTicksAfterFirstClose
          if otherTicksAfterFirstClose >= RequiredOtherTicks and win1.opened:
            close(win1)
      if ticks1 + ticks2 > TickLimit:
        forceCloseBoth()
    ,
    onClose: proc(e: CloseEvent) =
      discard,
  )

  let win2Events = WindowEventsHandler(
    onTick: proc(e: TickEvent) =
      inc ticks2
      if not closeLeftFirst:
        if not closeIssued and ticks2 >= CloseAtTick:
          closeIssued = true
          close(win2)
      else:
        if not win1.opened:
          firstObservedClosed = true
          inc otherTicksAfterFirstClose
          if otherTicksAfterFirstClose >= RequiredOtherTicks and win2.opened:
            close(win2)
      if ticks1 + ticks2 > TickLimit:
        forceCloseBoth()
    ,
    onClose: proc(e: CloseEvent) =
      discard,
  )

  runMultiple(
    (window: win1, eventsHandler: win1Events, makeVisible: true),
    (window: win2, eventsHandler: win2Events, makeVisible: true),
  )

  result = (
    otherTicksAfterFirstClose: otherTicksAfterFirstClose,
    firstObservedClosed: firstObservedClosed,
  )

suite "siwin multiwindow close":
  test "close left then keep right alive":
    block runCloseLeft:
      var stats: CloseStats
      try:
        stats = runCloseDirection(closeLeftFirst = true)
      except CatchableError:
        skip()
        break runCloseLeft
      check stats.firstObservedClosed
      check stats.otherTicksAfterFirstClose >= RequiredOtherTicks

  test "close right then keep left alive":
    block runCloseRight:
      var stats: CloseStats
      try:
        stats = runCloseDirection(closeLeftFirst = false)
      except CatchableError:
        skip()
        break runCloseRight
      check stats.firstObservedClosed
      check stats.otherTicksAfterFirstClose >= RequiredOtherTicks
