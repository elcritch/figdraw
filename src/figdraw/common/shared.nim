import std/[sequtils, tables, hashes]
import std/[unicode, strformat]
when not defined(js):
  import std/os
  import pkg/variant

export sequtils, strformat, tables, hashes
when not defined(js):
  export variant

import extras, uimaths
export extras, uimaths

import pkg/chroma

type FigDrawError* = object of CatchableError

type
  AppMainThreadEff* = object of RootEffect
  RenderThreadEff* = object of RootEffect

{.push hint[Name]: off.}
proc AppMainThread*() {.tags: [AppMainThreadEff].} =
  discard

proc RenderThread*() {.tags: [RenderThreadEff].} =
  discard

template threadEffects*(arg: typed) =
  arg()

{.pop.}

when defined(nimscript):
  {.pragma: runtimeVar, compileTime.}
else:
  {.pragma: runtimeVar, global.}

const
  clearColor* = color(0, 0, 0, 0)
  whiteColor* = color(1, 1, 1, 1)
  blackColor* = color(0, 0, 0, 1)
  blueColor* = color(0, 0, 1, 1)

type
  ScaleInfo* = object
    x*: float32
    y*: float32

  AppState* = object
    running*: bool
    requestedFrame*: int = 2
    lastDraw*: int
    lastTick*: int

    uiScale*: float32
    autoUiScale*: bool
    pixelScale*: float32

var
  dataDirStr* {.runtimeVar.}: string =
    when defined(js):
      "data"
    else:
      os.getCurrentDir() / "data"
  app* {.runtimeVar.} =
    AppState(running: true, uiScale: 1.0, autoUiScale: true, pixelScale: 1.0)

proc figDataDir*(): string =
  dataDirStr

proc setFigDataDir*(dir: string) =
  dataDirStr = dir

proc scaled*(a: Rect): Rect =
  a * app.uiScale

proc descaled*(a: Rect): Rect =
  let a = a / app.uiScale
  result.x = a.x
  result.y = a.y
  result.w = a.w
  result.h = a.h

proc scaled*(a: Vec2): Vec2 =
  a * app.uiScale

proc descaled*(a: Vec2): Vec2 =
  let a = a / app.uiScale
  result.x = a.x
  result.y = a.y

proc scaled*(a: float32): float32 =
  a.float32 * app.uiScale

proc descaled*(a: float32): float32 =
  a / app.uiScale
