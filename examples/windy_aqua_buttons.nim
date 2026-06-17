when defined(emscripten):
  import std/[strutils, times]
else:
  import std/[os, strutils, times]

import chroma

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

type AquaButtonKind = enum
  abkNormal
  abkDefault

type AquaAccent = enum
  aaGraphite
  aaBlue

proc addRect(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    fill: Fill,
    corners: float32,
    zlevel = 0.ZLevel,
    flags: set[FigFlags] = {},
    rotation = 0.0'f32,
    stroke = RenderStroke(),
    shadows: array[ShadowCount, RenderShadow] =
      [RenderShadow(), RenderShadow(), RenderShadow(), RenderShadow()],
): FigIdx {.discardable.} =
  renders.addChild(
    zlevel,
    parent,
    Fig(
      kind: nkRectangle,
      zlevel: zlevel,
      screenBox: box,
      fill: fill,
      corners: [corners, corners, corners, corners],
      flags: flags,
      rotation: rotation,
      stroke: stroke,
      shadows: shadows,
    ),
  )

proc addText(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    color: Color,
    offset = vec2(0.0'f32, 0.0'f32),
    zlevel = 0.ZLevel,
    hAlign = Center,
    vAlign = Middle,
) =
  discard renders.addChild(
    zlevel,
    parent,
    Fig(
      kind: nkText,
      zlevel: zlevel,
      screenBox: box + rect(offset.x, offset.y, 0, 0),
      fill: clearColor,
      textLayout: typeset(
        rect(0, 0, box.w, box.h),
        [(fs(font, color), text)],
        hAlign = hAlign,
        vAlign = vAlign,
        minContent = false,
        wrap = false,
      ),
    ),
  )

proc aquaAccent(accent: AquaAccent): tuple[top, bottom, stroke, gloss: ColorRGBA] =
  case accent
  of aaGraphite:
    (
      top: rgba(239, 240, 239, 255),
      bottom: rgba(126, 128, 126, 255),
      stroke: rgba(84, 86, 84, 230),
      gloss: rgba(255, 255, 255, 125),
    )
  of aaBlue:
    (
      top: rgba(85, 211, 255, 255),
      bottom: rgba(0, 124, 238, 255),
      stroke: rgba(0, 82, 191, 245),
      gloss: rgba(255, 255, 255, 150),
    )

proc addAquaRadioButton(
    renders: var Renders, root: FigIdx, box: Rect, selected: bool, accent = aaBlue
) =
  let radius = min(box.w, box.h) / 2.0'f32

  discard renders.addRect(
    root, box + rect(0.0'f32, 1.0'f32, 0.0'f32, 0.0'f32), rgba(0, 0, 0, 32), radius
  )

  let outer = renders.addRect(
    root,
    box,
    linear(rgba(253, 253, 250, 255), rgba(166, 168, 164, 255), axis = fgaY),
    radius,
    stroke = RenderStroke(weight: 0.8'f32, fill: rgba(108, 111, 107, 220)),
    shadows = [
      RenderShadow(
        style: InnerShadow,
        blur: 2.4'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 1.0'f32,
        fill: rgba(0, 0, 0, 48).color,
      ),
      RenderShadow(
        style: InnerShadow,
        blur: 2.2'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: -1.0'f32,
        fill: rgba(255, 255, 255, 90).color,
      ),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let
    innerInset = if selected: 1.6'f32 else: 2.0'f32
    inner = rect(
      box.x + innerInset,
      box.y + innerInset,
      box.w - innerInset * 2.0'f32,
      box.h - innerInset * 2.0'f32,
    )
    innerRadius = max(1.0'f32, min(inner.w, inner.h) / 2.0'f32)
    a = aquaAccent(accent)
    innerFill =
      if selected:
        linear(rgba(120, 230, 255, 255), a.bottom, axis = fgaDiagTLBR)
      else:
        linear(rgba(255, 255, 255, 255), rgba(235, 235, 232, 255), axis = fgaY)
    innerShadows =
      if selected:
        [
          RenderShadow(
            style: InnerShadow,
            blur: 2.8'f32,
            spread: 0.0'f32,
            x: 0.0'f32,
            y: 1.0'f32,
            fill: rgba(0, 58, 142, 86).color,
          ),
          RenderShadow(
            style: InnerShadow,
            blur: 2.8'f32,
            spread: 0.0'f32,
            x: -1.0'f32,
            y: -1.0'f32,
            fill: rgba(255, 255, 255, 80).color,
          ),
          RenderShadow(
            style: InnerShadow,
            blur: 3.8'f32,
            spread: 0.0'f32,
            x: 1.0'f32,
            y: 0.0'f32,
            fill: rgba(0, 51, 120, 46).color,
          ),
          RenderShadow(),
        ]
      else:
        [
          RenderShadow(
            style: InnerShadow,
            blur: 2.5'f32,
            spread: 0.0'f32,
            x: 0.0'f32,
            y: 1.0'f32,
            fill: rgba(0, 0, 0, 30).color,
          ),
          RenderShadow(
            style: InnerShadow,
            blur: 2.0'f32,
            spread: 0.0'f32,
            x: 0.0'f32,
            y: -1.0'f32,
            fill: rgba(255, 255, 255, 115).color,
          ),
          RenderShadow(),
          RenderShadow(),
        ]

  discard renders.addRect(
    outer,
    inner,
    innerFill,
    innerRadius,
    stroke =
      if selected:
        RenderStroke(weight: 0.5'f32, fill: a.stroke)
      else:
        RenderStroke(weight: 0.5'f32, fill: rgba(201, 203, 199, 200)),
    shadows = innerShadows,
  )

  discard renders.addRect(
    outer,
    if selected:
      rect(box.x + 4.5'f32, box.y + 2.8'f32, box.w - 9.0'f32, 2.7'f32)
    else:
      rect(box.x + 3.4'f32, box.y + 2.5'f32, box.w - 6.8'f32, 2.2'f32),
    if selected:
      linear(rgba(255, 255, 255, 135), rgba(255, 255, 255, 0), axis = fgaY)
    else:
      linear(rgba(255, 255, 255, 190), rgba(255, 255, 255, 18), axis = fgaY),
    if selected: 1.35'f32 else: 1.1'f32,
  )

  if selected:
    let
      pupilSize = min(box.w, box.h) * 0.34'f32
      pupil = rect(
        box.x + (box.w - pupilSize) / 2.0'f32,
        box.y + (box.h - pupilSize) / 2.0'f32,
        pupilSize,
        pupilSize,
      )
      pupilRadius = pupilSize / 2.0'f32
    discard renders.addRect(
      outer,
      pupil,
      linear(rgba(44, 66, 87, 248), rgba(6, 22, 44, 248), axis = fgaY),
      pupilRadius,
      stroke = RenderStroke(weight: 0.4'f32, fill: rgba(0, 0, 0, 145)),
    )
    discard renders.addRect(
      outer,
      rect(pupil.x + 1.1'f32, pupil.y + 0.9'f32, pupil.w - 2.2'f32, 1.0'f32),
      rgba(255, 255, 255, 85),
      0.5'f32,
    )

proc addCheckMark(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    markFill: Fill,
    shadowColor: ColorRGBA,
    shineColor: ColorRGBA,
) =
  let
    markX = box.x - box.w * 0.06'f32
    shortSeg = rect(
      markX + box.w * 0.18'f32, box.y + box.h * 0.56'f32, box.w * 0.42'f32, 2.6'f32
    )
    longSeg = rect(
      markX + box.w * 0.37'f32, box.y + box.h * 0.45'f32, box.w * 0.62'f32, 2.6'f32
    )

  discard renders.addRect(
    parent,
    shortSeg + rect(0.6'f32, 0.8'f32, 0.0'f32, 0.0'f32),
    shadowColor,
    1.3'f32,
    rotation = 43.0'f32,
  )
  discard renders.addRect(
    parent,
    longSeg + rect(0.6'f32, 0.8'f32, 0.0'f32, 0.0'f32),
    shadowColor,
    1.3'f32,
    rotation = -48.0'f32,
  )

  discard renders.addRect(parent, shortSeg, markFill, 1.3'f32, rotation = 43.0'f32)
  discard renders.addRect(parent, longSeg, markFill, 1.3'f32, rotation = -48.0'f32)

  discard renders.addRect(
    parent,
    rect(shortSeg.x + 0.5'f32, shortSeg.y + 0.1'f32, shortSeg.w * 0.68'f32, 0.8'f32),
    shineColor,
    0.4'f32,
    rotation = 43.0'f32,
  )
  discard renders.addRect(
    parent,
    rect(longSeg.x + 0.6'f32, longSeg.y + 0.1'f32, longSeg.w * 0.68'f32, 0.8'f32),
    shineColor,
    0.4'f32,
    rotation = -48.0'f32,
  )

proc addAquaCheckButton(
    renders: var Renders, root: FigIdx, box: Rect, checked: bool, accent = aaBlue
) =
  discard renders.addRect(
    root, box + rect(0.0'f32, 1.0'f32, 0.0'f32, 0.0'f32), rgba(0, 0, 0, 36), 2.5'f32
  )

  let
    a = aquaAccent(accent)
    buttonFill =
      if checked:
        linear(rgba(122, 232, 255, 255), a.bottom, axis = fgaDiagTLBR)
      else:
        linear(rgba(255, 255, 255, 255), rgba(214, 215, 212, 255), axis = fgaY)
    strokeFill =
      if checked:
        a.stroke
      else:
        rgba(88, 90, 88, 220)
    buttonShadows =
      if checked:
        [
          RenderShadow(
            style: InnerShadow,
            blur: 3.0'f32,
            spread: 0.0'f32,
            x: 0.0'f32,
            y: 1.0'f32,
            fill: rgba(0, 54, 130, 82).color,
          ),
          RenderShadow(
            style: InnerShadow,
            blur: 2.2'f32,
            spread: 0.0'f32,
            x: -1.0'f32,
            y: -1.0'f32,
            fill: rgba(255, 255, 255, 82).color,
          ),
          RenderShadow(
            style: InnerShadow,
            blur: 3.0'f32,
            spread: 0.0'f32,
            x: 1.0'f32,
            y: 0.0'f32,
            fill: rgba(0, 41, 100, 42).color,
          ),
          RenderShadow(),
        ]
      else:
        [
          RenderShadow(
            style: InnerShadow,
            blur: 2.5'f32,
            spread: 0.0'f32,
            x: 0.0'f32,
            y: 1.0'f32,
            fill: rgba(0, 0, 0, 32).color,
          ),
          RenderShadow(
            style: InnerShadow,
            blur: 2.0'f32,
            spread: 0.0'f32,
            x: 0.0'f32,
            y: -1.0'f32,
            fill: rgba(255, 255, 255, 112).color,
          ),
          RenderShadow(),
          RenderShadow(),
        ]
    outer = renders.addRect(
      root,
      box,
      buttonFill,
      2.5'f32,
      stroke = RenderStroke(weight: 1.0'f32, fill: strokeFill),
      flags = {NfRectMaskContent},
      shadows = buttonShadows,
    )

  discard renders.addRect(
    outer,
    if checked:
      rect(box.x + 1.5'f32, box.y + 1.1'f32, box.w - 3.0'f32, 3.1'f32)
    else:
      rect(box.x + 1.4'f32, box.y + 1.1'f32, box.w - 2.8'f32, 2.6'f32),
    if checked:
      linear(rgba(255, 255, 255, 142), rgba(255, 255, 255, 0), axis = fgaY)
    else:
      linear(rgba(255, 255, 255, 178), rgba(255, 255, 255, 20), axis = fgaY),
    if checked: 1.4'f32 else: 1.1'f32,
  )

  if checked:
    let
      markFill =
        if accent == aaBlue:
          linear(rgba(7, 76, 122, 245), rgba(3, 17, 45, 245), axis = fgaY)
        else:
          linear(rgba(80, 82, 78, 245), rgba(20, 22, 20, 245), axis = fgaY)
      markShine =
        if accent == aaBlue:
          rgba(255, 255, 255, 76)
        else:
          rgba(255, 255, 255, 92)
      markShadow =
        if accent == aaBlue:
          rgba(0, 16, 38, 72)
        else:
          rgba(0, 0, 0, 70)
    addCheckMark(renders, outer, box, markFill, markShadow, markShine)

proc addAquaPopupMenu(
    renders: var Renders, root: FigIdx, box: Rect, font: FigFont, text: string
) =
  discard renders.addRect(
    root, box + rect(0.0'f32, 1.6'f32, 0.0'f32, 0.0'f32), rgba(0, 0, 0, 58), 5.0'f32
  )
  discard renders.addRect(
    root, box + rect(0.8'f32, 2.2'f32, -0.8'f32, -0.2'f32), rgba(0, 0, 0, 24), 4.6'f32
  )

  let popupShadows = [
    RenderShadow(
      style: InnerShadow,
      blur: 3.0'f32,
      spread: 0.0'f32,
      x: 0.0'f32,
      y: 1.0'f32,
      fill: rgba(0, 0, 0, 46).color,
    ),
    RenderShadow(
      style: InnerShadow,
      blur: 2.4'f32,
      spread: 0.0'f32,
      x: 0.0'f32,
      y: -1.0'f32,
      fill: rgba(255, 255, 255, 118).color,
    ),
    RenderShadow(
      style: InnerShadow,
      blur: 2.2'f32,
      spread: 0.0'f32,
      x: 1.0'f32,
      y: 0.0'f32,
      fill: rgba(0, 0, 0, 24).color,
    ),
    RenderShadow(
      style: InnerShadow,
      blur: 1.4'f32,
      spread: 0.0'f32,
      x: -1.0'f32,
      y: 0.0'f32,
      fill: rgba(255, 255, 255, 48).color,
    ),
  ]

  let outer = renders.addRect(
    root,
    box,
    linear(
      rgba(255, 255, 255, 255),
      rgba(238, 239, 237, 255),
      rgba(205, 207, 203, 255),
      axis = fgaY,
      midPos = 92'u8,
    ),
    5.0'f32,
    stroke = RenderStroke(weight: 1.0'f32, fill: rgba(86, 88, 86, 216)),
    flags = {NfRectMaskContent},
    shadows = popupShadows,
  )

  discard renders.addRect(
    outer,
    rect(box.x + 2.4'f32, box.y + 1.2'f32, box.w - 4.8'f32, 4.0'f32),
    linear(rgba(255, 255, 255, 185), rgba(255, 255, 255, 0), axis = fgaY),
    1.8'f32,
  )

  let
    arrowWidth = min(24.0'f32, box.w * 0.24'f32)
    arrowBox = rect(box.x + box.w - arrowWidth, box.y, arrowWidth, box.h)
    labelBox = rect(
      box.x + 8.0'f32, box.y + 1.0'f32, box.w - arrowWidth - 12.0'f32, box.h - 2.0'f32
    )
    arrowFont =
      FigFont(typefaceId: font.typefaceId, size: max(9.0'f32, font.size - 4.0'f32))

  let arrowShadows = [
    RenderShadow(
      style: InnerShadow,
      blur: 2.5'f32,
      spread: 0.0'f32,
      x: 0.0'f32,
      y: 1.0'f32,
      fill: rgba(0, 56, 142, 78).color,
    ),
    RenderShadow(
      style: InnerShadow,
      blur: 2.0'f32,
      spread: 0.0'f32,
      x: -1.0'f32,
      y: -1.0'f32,
      fill: rgba(255, 255, 255, 92).color,
    ),
    RenderShadow(),
    RenderShadow(),
  ]

  discard renders.addRect(
    outer,
    arrowBox,
    linear(
      rgba(125, 230, 255, 255),
      rgba(38, 171, 251, 255),
      rgba(0, 112, 224, 255),
      axis = fgaY,
      midPos = 104'u8,
    ),
    0.0'f32,
    shadows = arrowShadows,
  )
  discard renders.addRect(
    outer,
    rect(arrowBox.x, arrowBox.y, 1.0'f32, arrowBox.h),
    linear(rgba(0, 70, 168, 165), rgba(0, 40, 112, 205), axis = fgaY),
    0.0'f32,
  )
  discard renders.addRect(
    outer,
    rect(arrowBox.x + 2.0'f32, arrowBox.y + 1.1'f32, arrowBox.w - 4.0'f32, 3.2'f32),
    linear(rgba(255, 255, 255, 132), rgba(255, 255, 255, 0), axis = fgaY),
    1.3'f32,
  )

  addText(
    renders, outer, labelBox, font, text, rgba(18, 18, 17, 244).color, hAlign = Left
  )
  addText(
    renders,
    outer,
    rect(arrowBox.x, arrowBox.y + 1.0'f32, arrowBox.w, arrowBox.h / 2.0'f32),
    arrowFont,
    "^",
    rgba(2, 38, 86, 245).color,
  )
  addText(
    renders,
    outer,
    rect(
      arrowBox.x,
      arrowBox.y + arrowBox.h / 2.0'f32 - 1.0'f32,
      arrowBox.w,
      arrowBox.h / 2.0'f32,
    ),
    arrowFont,
    "v",
    rgba(2, 38, 86, 245).color,
  )
  discard renders.addRect(
    outer,
    box,
    clearColor,
    5.0'f32,
    stroke = RenderStroke(weight: 1.1'f32, fill: rgba(72, 74, 72, 224)),
  )

proc aquaPalette(
    kind: AquaButtonKind
): tuple[outerTop, outerBottom, innerTop, innerBottom, midTop, midBottom: ColorRGBA] =
  case kind
  of abkNormal:
    (
      outerTop: rgba(122, 123, 121, 255),
      outerBottom: rgba(245, 245, 243, 255),
      innerTop: rgba(250, 250, 248, 255),
      innerBottom: rgba(224, 225, 222, 255),
      midTop: rgba(255, 255, 255, 235),
      midBottom: rgba(191, 193, 190, 210),
    )
  of abkDefault:
    (
      outerTop: rgba(9, 32, 145, 255),
      outerBottom: rgba(41, 133, 235, 255),
      innerTop: rgba(171, 229, 255, 255),
      innerBottom: rgba(37, 143, 246, 255),
      midTop: rgba(232, 255, 255, 240),
      midBottom: rgba(87, 181, 255, 230),
    )

proc addAquaButton(
    renders: var Renders,
    root: FigIdx,
    box: Rect,
    font: FigFont,
    text: string,
    kind: AquaButtonKind,
) =
  let
    p = aquaPalette(kind)
    radius = box.h / 2.0'f32
    darkStroke =
      if kind == abkDefault:
        rgba(2, 28, 124, 255).color
      else:
        rgba(99, 100, 98, 215).color
    textColor =
      if kind == abkDefault:
        rgba(11, 28, 40, 245).color
      else:
        rgba(28, 28, 26, 242).color

  discard renders.addRect(
    root,
    box + rect(0, 1.5'f32, 0, 0),
    rgba(0, 0, 0, 55),
    radius,
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 7.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 2.5'f32,
        fill: rgba(0, 0, 0, 58).color,
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let outline = renders.addRect(
    root,
    box,
    linear(p.outerTop, p.outerBottom, axis = fgaY),
    radius,
    stroke = RenderStroke(weight: 1.0'f32, fill: darkStroke),
    flags = {NfRectMaskContent},
  )

  let
    inset = 2.5'f32
    inner = rect(
      box.x + inset, box.y + inset, box.w - inset * 2.0'f32, box.h - inset * 2.0'f32
    )
    innerRadius = max(1.0'f32, radius - inset)
    innerFillTop =
      if kind == abkDefault:
        rgba(178, 232, 255, 226)
      else:
        rgba(252, 252, 250, 218)
    innerFillBottom =
      if kind == abkDefault:
        rgba(42, 145, 246, 216)
      else:
        rgba(228, 229, 226, 204)
    lowerTint =
      if kind == abkDefault:
        rgba(71, 173, 255, 92)
      else:
        rgba(174, 176, 172, 74)

  discard renders.addRect(
    outline,
    inner,
    rgba(0, 0, 0, 0),
    innerRadius,
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 8.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 0.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(0, 30, 145, 42).color
          else:
            rgba(0, 0, 0, 30).color
        ),
      ),
      RenderShadow(
        style: DropShadow,
        blur: 7.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: -1.5'f32,
        fill: rgba(255, 255, 255, 72).color,
      ),
      RenderShadow(
        style: DropShadow,
        blur: 6.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 2.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(0, 42, 165, 30).color
          else:
            rgba(0, 0, 0, 22).color
        ),
      ),
      RenderShadow(),
    ],
  )

  let innerClip = renders.addRect(
    outline,
    inner,
    linear(innerFillTop, innerFillBottom, axis = fgaY),
    innerRadius,
    flags = {NfRectMaskContent},
    shadows = [
      RenderShadow(
        style: InnerShadow,
        blur: 8.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 2.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(255, 255, 255, 58).color
          else:
            rgba(255, 255, 255, 82).color
        ),
      ),
      RenderShadow(
        style: InnerShadow,
        blur: 7.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: -2.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(0, 25, 130, 32).color
          else:
            rgba(0, 0, 0, 24).color
        ),
      ),
      RenderShadow(
        style: InnerShadow,
        blur: 11.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 0.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(0, 35, 150, 18).color
          else:
            rgba(0, 0, 0, 14).color
        ),
      ),
      RenderShadow(),
    ],
  )

  let topGlow = rect(inner.x - 8.0'f32, inner.y + 1.0'f32, inner.w + 16.0'f32, 1.0'f32)
  discard renders.addRect(
    innerClip,
    topGlow,
    rgba(0, 0, 0, 0),
    0.0'f32,
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 5.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 1.2'f32,
        fill: rgba(255, 255, 255, if kind == abkDefault: 120'u8 else: 105'u8).color,
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let topGloss = rect(inner.x - 4.0'f32, inner.y, inner.w + 8.0'f32, inner.h * 0.62'f32)
  discard renders.addRect(
    innerClip,
    topGloss,
    linear(
      rgba(255, 255, 255, if kind == abkDefault: 176'u8 else: 154'u8),
      rgba(255, 255, 255, 0),
      axis = fgaY,
    ),
    0.0'f32,
  )

  let lowerWash = rect(
    inner.x - 4.0'f32,
    inner.y + inner.h * 0.36'f32,
    inner.w + 8.0'f32,
    inner.h * 0.64'f32,
  )
  discard renders.addRect(
    innerClip,
    lowerWash,
    linear(rgba(255, 255, 255, 0), lowerTint, axis = fgaY),
    0.0'f32,
  )

  let waistGlow =
    rect(inner.x - 8.0'f32, inner.y + inner.h * 0.49'f32, inner.w + 16.0'f32, 1.0'f32)
  discard renders.addRect(
    innerClip,
    waistGlow,
    rgba(0, 0, 0, 0),
    0.0'f32,
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 7.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 0.8'f32,
        fill: rgba(255, 255, 255, if kind == abkDefault: 44'u8 else: 34'u8).color,
      ),
      RenderShadow(
        style: DropShadow,
        blur: 8.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: 4.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(31, 127, 244, 34).color
          else:
            rgba(0, 0, 0, 18).color
        ),
      ),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let bottomGlow =
    rect(inner.x - 8.0'f32, inner.y + inner.h - 1.0'f32, inner.w + 16.0'f32, 1.0'f32)
  discard renders.addRect(
    innerClip,
    bottomGlow,
    rgba(0, 0, 0, 0),
    0.0'f32,
    shadows = [
      RenderShadow(
        style: DropShadow,
        blur: 6.0'f32,
        spread: 0.0'f32,
        x: 0.0'f32,
        y: -2.0'f32,
        fill: (
          if kind == abkDefault:
            rgba(210, 246, 255, 58).color
          else:
            rgba(255, 255, 255, 44).color
        ),
      ),
      RenderShadow(),
      RenderShadow(),
      RenderShadow(),
    ],
  )

  let labelBox = rect(box.x, box.y + 1.0'f32, box.w, box.h - 1.0'f32)
  addText(
    renders, root, labelBox, font, text, rgba(255, 255, 255, 120).color, vec2(0, 1)
  )
  addText(
    renders, root, labelBox, font, text, rgba(0, 0, 0, 80).color, vec2(0, -0.6'f32)
  )
  addText(renders, root, labelBox, font, text, textColor)

proc makeRenderTree*(w, h: float32, font: FigFont): Renders =
  result = Renders()

  let root = result.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: linear(rgba(239, 240, 239, 255), rgba(211, 214, 214, 255), axis = fgaY),
    ),
  )

  for y in countup(0, int(ceil(h)), 4):
    discard result.addChild(
      0.ZLevel,
      root,
      Fig(
        kind: nkRectangle,
        zlevel: 0.ZLevel,
        screenBox: rect(0, y.float32, w, 1.0'f32),
        fill: rgba(255, 255, 255, 95),
      ),
    )

  let
    buttonW = 142.0'f32
    buttonH = 36.0'f32
    gap = 18.0'f32
    totalW = buttonW * 2.0'f32 + gap
    startX = floor((w - totalW) / 2.0'f32)
    y = 32.0'f32

  addAquaButton(
    result, root, rect(startX, y, buttonW, buttonH), font, "Cancel", abkNormal
  )
  addAquaButton(
    result,
    root,
    rect(startX + buttonW + gap, y, buttonW, buttonH),
    font,
    "OK",
    abkDefault,
  )

  let
    smallFont = FigFont(typefaceId: font.typefaceId, size: 13.0'f32)
    controlsW = 376.0'f32
    controlsX = max(24.0'f32, floor((w - controlsW) / 2.0'f32))
    controlsY = y + buttonH + 28.0'f32
    controlSize = 16.0'f32

  addAquaRadioButton(
    result,
    root,
    rect(controlsX, controlsY + 4.0'f32, controlSize, controlSize),
    true,
    aaBlue,
  )
  addAquaRadioButton(
    result,
    root,
    rect(controlsX + 28.0'f32, controlsY + 4.0'f32, controlSize, controlSize),
    false,
  )

  addAquaCheckButton(
    result,
    root,
    rect(controlsX + 82.0'f32, controlsY + 4.0'f32, controlSize, controlSize),
    false,
  )
  addAquaCheckButton(
    result,
    root,
    rect(controlsX + 110.0'f32, controlsY + 4.0'f32, controlSize, controlSize),
    true,
    aaGraphite,
  )
  addAquaCheckButton(
    result,
    root,
    rect(controlsX + 138.0'f32, controlsY + 4.0'f32, controlSize, controlSize),
    true,
    aaBlue,
  )

  addAquaPopupMenu(
    result,
    root,
    rect(controlsX + 202.0'f32, controlsY, 162.0'f32, 24.0'f32),
    smallFont,
    "Popup menu",
  )

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var appRunning = true
  let
    title = windyWindowTitle("Aqua Buttons")
    baseSize = ivec2(520, 170)
    window = newWindyWindow(size = baseSize, fullscreen = false, title = title)

  if getEnv("HDI") != "":
    setFigUiScale getEnv("HDI").parseFloat()
  else:
    setFigUiScale window.contentScale()
  if baseSize != baseSize.scaled():
    window.size = baseSize.scaled()

  let
    typefaceId = loadTypeface("Ubuntu.ttf")
    labelFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    renderer = newFigRenderer(atlasSize = 2048, backendState = WindyRenderBackend())

  renderer.setupBackend(window)

  var
    frames = 0
    fpsFrames = 0
    fpsStart = epochTime()

  proc redraw() =
    renderer.beginFrame()
    let logicalSize = window.logicalSize()
    var renders = makeRenderTree(logicalSize.x, logicalSize.y, labelFont)
    renderer.renderFrame(renders, logicalSize)
    renderer.endFrame()

  window.onCloseRequest = proc() =
    appRunning = false

  window.onResize = proc() =
    redraw()

  try:
    while appRunning:
      pollEvents()
      redraw()

      inc frames
      inc fpsFrames
      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        echo "fps: ", fpsFrames.float / elapsed
        fpsFrames = 0
        fpsStart = now

      if RunOnce and frames >= 1:
        appRunning = false
  finally:
    when not defined(emscripten):
      window.close()
