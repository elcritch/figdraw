import std/[options, hashes]
import chroma, stack_strings

import common/uimaths
import common/fonttypes
import common/imgutils

export uimaths, fonttypes, imgutils
export options, chroma, stack_strings

const
  ShadowCount* {.intdefine.} = 4

type
  FigID* = int64

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
    nkMsdfImage
    nkMtsdfImage

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
    NfSelectText

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

  MsdfImageStyle* = object
    color*: Color
    id*: ImageId
    pxRange*: float32
    sdThreshold*: float32
    ## If > 0, render as an outline (annular band) with this stroke width.
    ## Units are the same as other FigDraw weights and get UI-scaled at render time.
    strokeWeight*: float32

  FillGradientMode* = enum
    fgmNone
    fgmLinear

  FillGradientAxis* = enum
    fgaX
    fgaY
    fgaDiagTLBR
    fgaDiagBLTR

  FillGradient* = object
    mode*: FillGradientMode
    axis*: FillGradientAxis
    stopCount*: uint8      # 0, 2, or 3
    midPos*: uint8         # 0..255 (only used when stopCount == 3), default 128
    colors*: array[3, ColorRGBA]  # packed RGBA8

