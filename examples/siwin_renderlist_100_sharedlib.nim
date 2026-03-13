when defined(emscripten):
  import std/[times, monotimes, strformat]
else:
  import std/[os, times, monotimes, strformat]
import std/math

import ../bindings/generated/fig_draw

when defined(macosx):
  {.passL: "-Wl,-rpath,@executable_path/../bindings/generated".}
  {.passL: "-Wl,-rpath,@loader_path/../bindings/generated".}
elif defined(linux) or defined(bsd):
  {.passL: "-Wl,-rpath,$ORIGIN/../bindings/generated".}

const
  Copies = 100
  RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
  NoSleep {.booldefine: "figdraw.noSleep".}: bool = true
  TraceShared {.booldefine: "figdraw.traceSharedLib".}: bool = false

let
  redFill = RgbaColor(r: 220, g: 40, b: 40, a: 155)
  redStroke = RgbaColor(r: 0, g: 0, b: 0, a: 155)
  greenSolid = RgbaColor(r: 40, g: 180, b: 90, a: 155)
  greenGradStart = RgbaColor(r: 18, g: 112, b: 64, a: 255)
  greenGradMid = RgbaColor(r: 40, g: 180, b: 90, a: 255)
  greenGradStop = RgbaColor(r: 78, g: 224, b: 188, a: 255)
  blueSolid = RgbaColor(r: 60, g: 90, b: 220, a: 155)
  blueGradStart = RgbaColor(r: 44, g: 72, b: 186, a: 255)
  blueGradMid = RgbaColor(r: 60, g: 90, b: 220, a: 255)
  blueGradStop = RgbaColor(r: 118, g: 168, b: 255, a: 255)
  whiteStroke = RgbaColor(r: 255, g: 255, b: 255, a: 210)
  blackShadow = RgbaColor(r: 0, g: 0, b: 0, a: 155)
  blueInnerShadow = RgbaColor(r: 40, g: 40, b: 60, a: 150)
  redBorder = BorderSize(width: 5.0)
  blueBorder = BorderSize(width: 4.0)

proc fract(x: float64): float64 {.inline.} =
  x - floor(x)

proc buildRenderTree(renders: Renders, w, h: float32, frame: int) =
  if renders.isNil:
    quit("buildRenderTree: renders is nil", 1)
  renders.clear()
  let t = frame.float32 * 0.02'f32

  let background = newRectangleFig(0, 0, w, h)
  GC_ref(background)
  if background.isNil:
    quit("makeRenderTree: newRectangleFig returned nil", 1)
  when TraceShared:
    echo "trace: background created"
  background.setFillColorRgba(RgbaColor(r: 255, g: 255, b: 255, a: 155))
  when TraceShared:
    echo "trace: background fill set"
  discard renders.addRoot(0, background)
  when TraceShared:
    echo "trace: background root added"

  let redStartX = 60.0'f32
  let redStartY = 60.0'f32
  let greenStartX = 320.0'f32
  let greenStartY = 120.0'f32
  let blueStartX = 180.0'f32
  let blueStartY = 300.0'f32
  let maxW = 260.0'f32
  let maxH = 180.0'f32
  let maxX = max(0.0'f32, w - (greenStartX + maxW))
  let maxY = max(0.0'f32, h - (blueStartY + maxH))

  let loopCopies = when TraceShared: 1 else: Copies
  for i in 0 ..< loopCopies:
    when TraceShared:
      if i == 0:
        echo "trace: loop i=0 start"
    let
      seedX = sin(i.float64 * 78.233'f64) * 43758.5453'f64
      seedY = sin((i + 19).float64 * 37.719'f64) * 24634.6345'f64
      baseX = (if maxX > 0: (fract(seedX).float32 * maxX) else: 0'f32)
      baseY = (if maxY > 0: (fract(seedY).float32 * maxY) else: 0'f32)
      jitterX = sin((t + i.float32 * 0.15'f32).float64).float32 * 20
      jitterY = cos((t * 0.9'f32 + i.float32 * 0.2'f32).float64).float32 * 20
      offsetX = min(max(baseX + jitterX, 0'f32), maxX)
      offsetY = min(max(baseY + jitterY, 0'f32), maxY)
      sizePulseW = 0.5'f32 + 0.5'f32 * sin((t * 0.8'f32 + i.float32 * 0.07'f32).float64).float32
      sizePulseH = 0.5'f32 + 0.5'f32 * cos((t * 0.65'f32 + i.float32 * 0.09'f32).float64).float32
      redW = 160.0'f32 + 100.0'f32 * sizePulseW
      redH = 110.0'f32 + 70.0'f32 * sizePulseH
      greenW = 160.0'f32 + 100.0'f32 * sizePulseH
      greenH = 110.0'f32 + 70.0'f32 * sizePulseW
      blueW = 160.0'f32 + 100.0'f32 * (1.0'f32 - sizePulseW)
      blueH = 110.0'f32 + 70.0'f32 * (1.0'f32 - sizePulseH)

    let redFig = newRectangleFig(redStartX + offsetX, redStartY + offsetY, redW, redH)
    GC_ref(redFig)
    when TraceShared:
      if i == 0:
        echo "trace: red created"
    redFig.setFillColorRgba(redFill)
    let
      cornerPulse = 0.5'f32 + 0.5'f32 * sin((t * 1.25'f32 + i.float32 * 0.11'f32).float64).float32
      c0 = 4.0'f32 + 26.0'f32 * cornerPulse
      c1 = 6.0'f32 + 22.0'f32 * (1.0'f32 - cornerPulse)
      c2 = 8.0'f32 + 18.0'f32 * (0.5'f32 + 0.5'f32 * sin((t * 0.7'f32 + i.float32 * 0.05'f32).float64).float32)
      c3 = 10.0'f32 + 16.0'f32 * (0.5'f32 + 0.5'f32 * cos((t * 0.8'f32 + i.float32 * 0.06'f32).float64).float32)
    when not TraceShared:
      redFig.setCorners(
        CornerRadii(topLeft: c0, topRight: c1, bottomLeft: c2, bottomRight: c3)
      )
      redFig.setStroke(redBorder, redStroke)
    when TraceShared:
      if i == 0:
        echo "trace: red style (trace mode simplified)"
    discard renders.addRoot(0, redFig)
    when TraceShared:
      if i == 0:
        echo "trace: red added"

    let greenFig = newRectangleFig(greenStartX + offsetX, greenStartY + offsetY, greenW, greenH)
    GC_ref(greenFig)
    when TraceShared:
      if i == 0:
        echo "trace: green created"
    let useGreenGradient = (i mod 2) == 0
    when not TraceShared:
      if useGreenGradient:
        let axis = (if (i mod 4) < 2: 0'i8 else: 2'i8)
        greenFig.setFillLinear3(greenGradStart, greenGradMid, greenGradStop, axis, 128'u8)
      else:
        greenFig.setFillColorRgba(greenSolid)
    else:
      greenFig.setFillColorRgba(greenSolid)
    when TraceShared:
      if i == 0:
        echo "trace: green fill"
    let
      greenCornerPulse = 0.5'f32 + 0.5'f32 * cos((t * 0.95'f32 + i.float32 * 0.08'f32).float64).float32
      g0 = 6.0'f32 + 22.0'f32 * greenCornerPulse
      g1 = 8.0'f32 + 18.0'f32 * (1.0'f32 - greenCornerPulse)
      g2 = 10.0'f32 + 16.0'f32 * (0.5'f32 + 0.5'f32 * cos((t * 0.75'f32 + i.float32 * 0.04'f32).float64).float32)
      g3 = 12.0'f32 + 14.0'f32 * (0.5'f32 + 0.5'f32 * sin((t * 0.85'f32 + i.float32 * 0.05'f32).float64).float32)
      shadowPulse = 0.5'f32 + 0.5'f32 * sin((t * 1.1'f32 + i.float32 * 0.05'f32).float64).float32
      shadowBlur = max(0.0'f32, 6.0'f32 + 18.0'f32 * shadowPulse)
      shadowSpread = max(0.0'f32, 4.0'f32 + 20.0'f32 * (1.0'f32 - shadowPulse))
      shadowX = 6.0'f32 + 10.0'f32 * sin((t * 0.9'f32 + i.float32 * 0.03'f32).float64).float32
      shadowY = 6.0'f32 + 10.0'f32 * cos((t * 0.9'f32 + i.float32 * 0.03'f32).float64).float32
    when not TraceShared:
      greenFig.setCorners(
        CornerRadii(topLeft: g0, topRight: g1, bottomLeft: g2, bottomRight: g3)
      )
    when TraceShared:
      if i == 0:
        echo "trace: green corners"
    when not TraceShared:
      greenFig.clearShadows()
    when TraceShared:
      if i == 0:
        echo "trace: green clear shadows"
    when not TraceShared:
      greenFig.setShadow(0, 1, shadowBlur, shadowSpread, shadowX, shadowY, blackShadow)
    when TraceShared:
      if i == 0:
        echo "trace: green shadow"
    discard renders.addRoot(0, greenFig)
    when TraceShared:
      if i == 0:
        echo "trace: green added"

    let blueFig = newRectangleFig(blueStartX + offsetX, blueStartY + offsetY, blueW, blueH)
    GC_ref(blueFig)
    when TraceShared:
      if i == 0:
        echo "trace: blue created"
    let useBlueGradient = (i mod 3) == 0
    when not TraceShared:
      if useBlueGradient:
        let axis = (if (i mod 2) == 0: 1'i8 else: 3'i8)
        blueFig.setFillLinear3(blueGradStart, blueGradMid, blueGradStop, axis, 132'u8)
      else:
        blueFig.setFillColorRgba(blueSolid)
    else:
      blueFig.setFillColorRgba(blueSolid)
    when TraceShared:
      if i == 0:
        echo "trace: blue fill"
    when not TraceShared:
      blueFig.setStroke(blueBorder, whiteStroke)
    when TraceShared:
      if i == 0:
        echo "trace: blue stroke"
    let
      insetPulse = 0.5'f32 + 0.5'f32 * sin((t * 1.05'f32 + i.float32 * 0.06'f32).float64).float32
      insetBlur = max(0.0'f32, 8.0'f32 + 10.0'f32 * insetPulse)
      insetSpread = max(0.0'f32, 2.0'f32 + 10.0'f32 * (1.0'f32 - insetPulse))
      insetX = 6.0'f32 * sin((t * 0.85'f32 + i.float32 * 0.04'f32).float64).float32
      insetY = 6.0'f32 * cos((t * 0.8'f32 + i.float32 * 0.04'f32).float64).float32
    when not TraceShared:
      blueFig.clearShadows()
    when TraceShared:
      if i == 0:
        echo "trace: blue clear shadows"
    when not TraceShared:
      blueFig.setShadow(0, 2, insetBlur, insetSpread, insetX, insetY, blueInnerShadow)
    when TraceShared:
      if i == 0:
        echo "trace: blue shadow"
    discard renders.addRoot(0, blueFig)
    when TraceShared:
      if i == 0:
        echo "trace: blue added"

when isMainModule:
  when not defined(emscripten):
    let libDir = getCurrentDir() / "bindings" / "generated"
    when defined(macosx):
      let expected = libDir / "libfig_draw.dylib"
      let actual = libDir / "libfigdraw.dylib"
      if not fileExists(expected) and fileExists(actual):
        try:
          createSymlink("libfigdraw.dylib", expected)
        except OSError:
          discard
    elif defined(linux) or defined(bsd):
      let expected = libDir / "libfig_draw.so"
      let actual = libDir / "libfigdraw.so"
      if not fileExists(expected) and fileExists(actual):
        try:
          createSymlink("libfigdraw.so", expected)
        except OSError:
          discard
    setFigDataDir(getCurrentDir() / "data")

  var appRunning = true
  var globalFrame = 0

  let typeface = loadTypefaceBinding("Ubuntu.ttf")
  if typeface.isNil:
    quit("Failed to load typeface: Ubuntu.ttf", 1)
  let fpsFont = newFigFontBinding(typeface, 18.0'f32)
  if fpsFont.isNil:
    quit("Failed to create fps font", 1)
  var fpsText = "0.0 FPS"

  let title = "Siwin RenderList (Nim Shared Lib)"
  let renderer = newSiwinRendererBinding(512, 1.0'f32)
  if renderer.isNil:
    quit("Failed to create siwin renderer", 1)
  let window = newSiwinWindowBinding(
    800, 600, false, title, true, 0, true, false, false
  )
  if window.isNil:
    quit("Failed to create siwin window", 1)
  let autoScale = window.configureUiScaleBinding("")
  when TraceShared:
    echo "trace: configured ui scale"
  renderer.setupBackendBinding(window)
  when TraceShared:
    echo "trace: setup backend"
  window.firstStepWindowBinding(true)
  when TraceShared:
    echo "trace: first step"
  window.makeCurrentWindowBinding()
  when TraceShared:
    echo "trace: make current"

  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0
  var lastElementCount = 0
  let renders = newRenders()
  if renders.isNil:
    quit("Failed to create renders", 1)

  try:
    while window.windowIsOpenBinding() and appRunning:
      window.refreshUiScaleBinding(autoScale)
      when TraceShared:
        echo "trace: refresh ui scale"

      inc frames
      inc globalFrame
      inc fpsFrames

      renderer.beginFrameBinding()
      when TraceShared:
        echo "trace: begin frame"
      let width = window.logicalWidthBinding()
      let height = window.logicalHeightBinding()
      when TraceShared:
        echo "trace: logical size ", width, "x", height

      let t0 = getMonoTime()
      buildRenderTree(renders, width, height, globalFrame)
      when TraceShared:
        echo "trace: make render tree done"
      makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)
      lastElementCount = renders.layerNodeCount(0)

      let
        hudMargin = 12.0'f32
        hudW = 180.0'f32
        hudH = 34.0'f32
        hudX = width - hudW - hudMargin
        hudY = hudMargin
      let hudRect = newRectangleFig(hudX, hudY, hudW, hudH)
      GC_ref(hudRect)
      hudRect.setFillColorRgba(RgbaColor(r: 0, g: 0, b: 0, a: 155))
      hudRect.setCorners(CornerRadii(topLeft: 8, topRight: 8, bottomLeft: 8, bottomRight: 8))
      discard renders.addRoot(0, hudRect)

      let
        hudTextPadX = 10.0'f32
        hudTextPadY = 6.0'f32
        hudTextX = hudX + hudTextPadX
        hudTextY = hudY + hudTextPadY
        hudTextW = hudW - hudTextPadX * 2
        hudTextH = hudH - hudTextPadY * 2

      let fpsLayout = typesetTextBinding(
        hudTextW,
        hudTextH,
        fpsFont,
        fpsText,
        hAlign = 2, # Right
        vAlign = 1, # Middle
        minContent = false,
        wrap = false,
      )
      if not fpsLayout.isNil:
        let hudText = newTextFig(hudTextX, hudTextY, hudTextW, hudTextH)
        GC_ref(hudText)
        hudText.setFillColorRgba(RgbaColor(r: 0, g: 0, b: 0, a: 0))
        setFigTextLayoutBinding(hudText, fpsLayout)
        discard renders.addRoot(0, hudText)
      when TraceShared:
        echo "trace: hud text done"

      let t1 = getMonoTime()
      renderer.renderFrameBinding(renders, width, height)
      when TraceShared:
        echo "trace: render frame done"
      renderFrameMsSum += float((getMonoTime() - t1).inMilliseconds)
      renderer.endFrameBinding()
      when TraceShared:
        echo "trace: end frame"
      window.presentNowBinding()
      when TraceShared:
        echo "trace: present"

      window.redrawWindowBinding()
      window.stepWindowBinding()
      when TraceShared:
        echo "trace: step"

      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        fpsText = fmt"{fps:0.1f} FPS"
        let avgMake = makeRenderTreeMsSum / max(1, fpsFrames).float
        let avgRender = renderFrameMsSum / max(1, fpsFrames).float
        echo "fps: ",
          fps, " | elems: ", lastElementCount, " | makeRenderTree avg(ms): ", avgMake,
          " | renderFrame avg(ms): ", avgRender
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0

      when RunOnce:
        if frames >= 1:
          appRunning = false

      when not NoSleep and not defined(emscripten):
        if appRunning:
          sleep(16)
  finally:
    when not TraceShared:
      window.closeWindowBinding()
