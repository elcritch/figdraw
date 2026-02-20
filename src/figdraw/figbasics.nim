import std/[options, hashes, math]
import chroma, stack_strings

import common/uimaths
import common/fonttypes
import common/imgutils

export uimaths, fonttypes, imgutils
export options, chroma, stack_strings

const ShadowCount* {.intdefine.} = 4

type
  FigID* = int64
  ZLevel* = int8

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

  ShadowStyle* = enum
    ## Supports drop and inner shadows.
    NoShadow
    DropShadow
    InnerShadow

  FillGradientAxis* = enum
    fgaX
    fgaY
    fgaDiagTLBR
    fgaDiagBLTR

  FillKind* = enum
    flColor
    flLinear2
    flLinear3

  Linear2* = object
    axis*: FillGradientAxis
    start*: ColorRGBA # packed RGBA8
    stop*: ColorRGBA # packed RGBA8

  Linear3* = object
    axis*: FillGradientAxis
    start*: ColorRGBA # packed RGBA8
    mid*: ColorRGBA # packed RGBA8
    stop*: ColorRGBA # packed RGBA8
    midPos*: uint8 # 0..255

  Fill* = object
    case kind*: FillKind
    of flColor:
      color*: ColorRGBA
    of flLinear2:
      lin2*: Linear2
    of flLinear3:
      lin3*: Linear3

  RenderShadow* = object
    style*: ShadowStyle
    fill*: Fill
    blur*: float32
    spread*: float32
    x*: float32
    y*: float32

  RenderStroke* = object
    weight*: float32
    fill*: Fill

  ImageStyle* = object
    id*: ImageId
    fill*: Fill

  MsdfImageStyle* = object
    id*: ImageId
    fill*: Fill
    pxRange*: float32
    sdThreshold*: float32
    ## If > 0, render as an outline (annular band) with this stroke width.
    ## Units are the same as other FigDraw weights and get UI-scaled at render time.
    strokeWeight*: float32

proc fill*(color: ColorRGBA): Fill =
  Fill(kind: flColor, color: color)

proc fillLinear*(start, stop: ColorRGBA, axis: FillGradientAxis): Fill =
  Fill(kind: flLinear2, lin2: Linear2(axis: axis, start: start, stop: stop))

proc fillLinear*(
    start, mid, stop: ColorRGBA, axis: FillGradientAxis, midPos = 128'u8
): Fill =
  Fill(
    kind: flLinear3,
    lin3: Linear3(axis: axis, start: start, mid: mid, stop: stop, midPos: midPos),
  )

#converter toColorRGBA*(c: Color): ColorRGBA {.inline.} =
#  ## Backward compatibility for callers still producing float colors.
#  rgba(c)

converter toFill*(c: ColorRGBA): Fill {.inline.} =
  ## Backward compatibility for callers still producing float colors.
  fill(c)

converter toFill*(c: Color): Fill {.inline.} =
  ## Backward compatibility for callers still producing float colors.
  fill(rgba(c))

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

converter toCornerRadii*[T: SomeNumber](
    a: array[4, T]
): array[DirectionCorners, uint16] =
  for i in 0 ..< 4:
    result[DirectionCorners(i)] = cornerToU16(a[i])

converter toCornerRadii*[T: SomeNumber](
    a: array[DirectionCorners, T]
): array[DirectionCorners, uint16] =
  for c in DirectionCorners:
    result[c] = cornerToU16(a[c])
