import std/[options, hashes]
import chroma
when not defined(js):
  import stack_strings

import common/uimaths
import common/fonttypes
when defined(js):
  import common/imgutils_js as imgutils
else:
  import common/imgutils

export uimaths, fonttypes, imgutils
export options, chroma
when not defined(js):
  export stack_strings

const
  FigStringCap* {.intdefine.} = 48
  ShadowCount* {.intdefine.} = 4
  FigDrawNames* {.booldefine: "figdraw.names".}: bool = false

type
  FigID* = int64

when defined(js):
  type FigName* = string
else:
  type FigName* = StackString[FigStringCap]

type
  Directions* = enum
    dTop
    dRight
    dBottom
    dLeft

  DirectionCorners* = enum
    dcTopLeft
    dcTopRight
    dcBottomLeft
    dcBottomRight

  FigKind* = enum
    ## Different types of nodes.
    nkFrame
    nkText
    nkRectangle
    nkDrawable
    nkScrollBar
    nkImage

  FigFlags* = enum
    NfClipContent
    NfDisableRender
    NfScrollPanel
    NfDead
    NfPreDrawReady
    NfPostDrawReady
    NfContentsDrawReady
    NfRootWindow
    NfInitialized
    NfSkipLayout
    NfInactive

  ShadowStyle* = enum
    ## Supports drop and inner shadows.
    NoShadow
    DropShadow
    InnerShadow

  ZLevel* = int8

  RenderShadow* = object
    style*: ShadowStyle
    blur*: float32
    spread*: float32
    x*: float32
    y*: float32
    color*: Color

  RenderStroke* = object
    weight*: float32
    color*: Color

  ImageStyle* = object
    color*: Color
    id*: ImageId
