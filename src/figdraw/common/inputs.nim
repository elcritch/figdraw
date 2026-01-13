import std/options
import pkg/patty

import ../fignodes
import ./uimaths, ./keys

export uimaths, keys

type
  FrameStyle* {.pure.} = enum
    DecoratedResizable
    DecoratedFixedSized
    Undecorated
    Transparent

  WindowInfo* = object
    box*: Box
    running*: bool
    focused*: bool
    minimized*: bool
    fullscreen*: bool
    pixelRatio*: float32

variantp ClipboardContents:
  ClipboardEmpty
  ClipboardStr(str: string)

variantp RenderCommands:
  RenderQuit
  RenderUpdate(n: Renders, winInfo: WindowInfo)
  RenderSetTitle(name: string)
  RenderClipboardGet
  RenderClipboard(cb: ClipboardContents)

type
  AppInputs* = object
    empty*: bool
    mouse*: Mouse
    keyboard*: Keyboard

    buttonPress*: set[UiMouse]
    buttonDown*: set[UiMouse]
    buttonRelease*: set[UiMouse]
    buttonToggle*: set[UiMouse]

    keyPress*: set[UiKey]
    keyDown*: set[UiKey]
    keyRelease*: set[UiKey]
    keyToggle*: set[UiKey]

    window*: Option[WindowInfo]

