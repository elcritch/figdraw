import std/[options, hashes, math]
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
    NfRootWindow
    NfInactive
    NfSelectText
    NfGradientInsetShadow

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

converter toColorRGBA*(c: Color): ColorRGBA {.inline.} =
  ## Backward compatibility for callers still producing float colors.
  rgba(c)

proc cornerToU16(v: SomeNumber): uint16 {.inline.} =
  when v is SomeFloat:
    if v <= 0:
      return 0'u16
    if v >= high(uint16).float:
      return high(uint16)
    round(v).uint16
  else:
    if v <= 0:
      return 0'u16
    if v >= high(uint16):
      return high(uint16)
    v.uint16

converter toCornerRadii*[T: SomeNumber](a: array[4, T]): array[DirectionCorners, uint16] =
  for i in 0 ..< 4:
    result[DirectionCorners(i)] = cornerToU16(a[i])

converter toCornerRadii*[T: SomeNumber](
    a: array[DirectionCorners, T]
): array[DirectionCorners, uint16] =
  for c in DirectionCorners:
    result[c] = cornerToU16(a[c])
