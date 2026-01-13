import std/tables

import ./inputs
import ./rchannels

export inputs

type
  AppFrame* = ref object
    uxInputList*: RChan[AppInputs]
    rendInputList*: RChan[RenderCommands]
    windowInfo*: WindowInfo
    windowTitle*: string
    windowStyle*: FrameStyle
    configFile*: string
    saveWindowState*: bool
    clipboards*: RChan[ClipboardContents]

