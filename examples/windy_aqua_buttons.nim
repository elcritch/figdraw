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

proc addRect(
    renders: var Renders,
    parent: FigIdx,
    box: Rect,
    fill: Fill,
    corners: float32,
    zlevel = 0.ZLevel,
    flags: set[FigFlags] = {},
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
        hAlign = Center,
        vAlign = Middle,
        minContent = false,
        wrap = false,
      ),
    ),
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
    y = floor((h - buttonH) / 2.0'f32)

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

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  var appRunning = true
  let
    title = windyWindowTitle("Aqua Buttons")
    baseSize = ivec2(420, 110)
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
