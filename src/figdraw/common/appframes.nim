import ./inputs

export inputs

type
  AppFrame* = ref object
    windowInfo*: WindowInfo
    windowTitle*: string
    windowStyle*: FrameStyle
    configFile*: string
    saveWindowState*: bool
