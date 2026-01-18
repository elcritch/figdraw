import bumpy, vmath

type
  WindowInfo* = object
    box*: Rect
    running*: bool
    focused*: bool
    minimized*: bool
    fullscreen*: bool
    pixelRatio*: float32

  AppFrame* = ref object
    windowInfo*: WindowInfo
    windowTitle*: string

