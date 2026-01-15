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
