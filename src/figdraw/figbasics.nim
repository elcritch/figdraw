import std/[options, hashes]
import chroma, stack_strings

import common/uimaths
import common/fonttypes

export uimaths, fonttypes
export options, chroma, stack_strings

const
  FigStringCap* {.intdefine.} = 48
  ShadowCount* {.intdefine.} = 4
  FigDrawNames* {.booldefine: "figdraw.names".}: bool = false

type
  FigName* = StackString[FigStringCap]
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

  Attributes* = enum ## user facing attributes
    SkipCss          ## Skip applying CSS to this node
    Hidden           ## Hidden from layout and rendering
    Disabled         ## Disabled from user interaction
    Active           ## Active from user interaction
    Checked          ## Checked from user interaction
    Open             ## Open from user interaction
    Selected         ## Selected from user interaction
    Hover            ## Hovered from user interaction
    Focusable        ## Focusable from user interaction
    Focus            ## Focused from user interaction
    FocusVisible     ## Focus visible from user interaction
    FocusWithin      ## Focus within from user interaction


  FieldSetAttrs* = enum
    ## For tracking which fields have been set by the widget user code.
    ##
    ## An example is setting `fill` in a button's code. We want this
    ## to override any defaults the widget itself my later set.
    ##
    ## ~~TODO: this is hacky, but efficient~~
    ## TODO: remove these...
    fsZLevel
    fsRotation
    fsCornerRadius
    fsClipContent
    fsFill
    fsFillHover
    fsHighlight
    fsStroke
    fsImage
    fsShadow
    fsSetGridCols
    fsSetGridRows
    fsGridAutoFlow
    fsGridAutoRows
    fsGridAutoColumns
    fsJustifyItems
    fsAlignItems

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

  ImageId* = distinct Hash

  ImageStyle* = object
    name*: FigName
    color*: Color
    id*: ImageId

proc `==`*(a, b: ImageId): bool {.borrow.}
