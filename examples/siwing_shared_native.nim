import std/[math, monotimes, os, strformat, times]

import figdraw_native_abi

when defined(macosx):
  {.passL: "-Wl,-rpath,@executable_path".}
  {.passL: "-Wl,-rpath,@loader_path".}
  {.passL: "-Wl,-rpath,@executable_path/../.nimcache/native_figdraw".}
  {.passL: "-Wl,-rpath,@loader_path/../.nimcache/native_figdraw".}
elif defined(linux) or defined(bsd):
  {.passL: "-Wl,-rpath,$ORIGIN".}
  {.passL: "-Wl,-rpath,$ORIGIN/../.nimcache/native_figdraw".}

const
  Copies = 100
  RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
  NoSleep {.booldefine: "figdraw.noSleep".}: bool = true

func rgba(r, g, b, a: uint8): ColorRGBA =
  ColorRGBA(r: r, g: g, b: b, a: a)

let
  redFill = rgba(220, 40, 40, 155)
  redStroke = rgba(0, 0, 0, 155)
  greenStart = rgba(18, 112, 64, 255)
  greenMiddle = rgba(40, 180, 90, 255)
  greenStop = rgba(78, 224, 188, 255)
  blueFill = rgba(60, 90, 220, 155)
  whiteStroke = rgba(255, 255, 255, 210)
  blackShadow = rgba(0, 0, 0, 155)

func fract(value: float64): float64 =
  value - floor(value)

proc buildRenderTree(renders: NativeRenders, width, height: float32, frame: int) =
  nativeClearRenders(renders)
  let background = Fig(
    kind: nkRectangle,
    screenBox: Rect(x: 0, y: 0, w: width, h: height),
    fill: fill(rgba(255, 255, 255, 155)),
  )
  discard nativeAddRoot(renders, 0, background)

  let
    time = frame.float32 * 0.02'f32
    maxX = max(0.0'f32, width - 580.0'f32)
    maxY = max(0.0'f32, height - 480.0'f32)

  for index in 0 ..< Copies:
    let
      seedX = sin(index.float64 * 78.233) * 43758.5453
      seedY = sin((index + 19).float64 * 37.719) * 24634.6345
      jitterX = sin((time + index.float32 * 0.15).float64).float32 * 20
      jitterY = cos((time * 0.9 + index.float32 * 0.2).float64).float32 * 20
      offsetX = min(max(fract(seedX).float32 * maxX + jitterX, 0), maxX)
      offsetY = min(max(fract(seedY).float32 * maxY + jitterY, 0), maxY)
      pulse = 0.5'f32 + 0.5'f32 * sin((time + index.float32 * 0.07).float64).float32
      inversePulse = 1.0'f32 - pulse
      corner = 4.0'f32 + 26.0'f32 * pulse

    let red = Fig(
      kind: nkRectangle,
      screenBox: Rect(
        x: 60 + offsetX,
        y: 60 + offsetY,
        w: 160 + 100 * pulse,
        h: 110 + 70 * inversePulse,
      ),
      fill: fill(redFill),
      corners: [corner.uint16, 12'u16, 20'u16, 8'u16],
      stroke: RenderStroke(weight: 5, fill: fill(redStroke)),
    )
    discard nativeAddRoot(renders, 0, red)

    var greenShadows: array[4, RenderShadow]
    greenShadows[0] = RenderShadow(
      style: DropShadow,
      fill: fill(blackShadow),
      blur: 8 + 14 * pulse,
      spread: 5,
      x: 8,
      y: 8,
    )
    let green = Fig(
      kind: nkRectangle,
      screenBox: Rect(
        x: 320 + offsetX,
        y: 120 + offsetY,
        w: 160 + 100 * inversePulse,
        h: 110 + 70 * pulse,
      ),
      fill: linear(
        greenStart,
        greenMiddle,
        greenStop,
        if index mod 2 == 0: fgaX else: fgaDiagTLBR,
        128,
      ),
      corners: [8'u16, corner.uint16, 16'u16, 24'u16],
      shadows: greenShadows,
    )
    discard nativeAddRoot(renders, 0, green)

    let blue = Fig(
      kind: nkRectangle,
      screenBox: Rect(
        x: 180 + offsetX, y: 300 + offsetY, w: 160 + 100 * pulse, h: 110 + 70 * pulse
      ),
      fill: fill(blueFill),
      stroke: RenderStroke(weight: 4, fill: fill(whiteStroke)),
    )
    discard nativeAddRoot(renders, 0, blue)

when isMainModule:
  nativeSetFigDataDir(getCurrentDir() / "data")

  let
    typeface = nativeLoadTypeface("Ubuntu.ttf")
    fpsFont = nativeNewFigFont(typeface, 18)
    app = nativeNewFigSiwinApp(
      800, 600, "Siwin RenderList (Native Nim Dynlib)", 512, 1.0, false, true, 0, true,
      false, false,
    )
    renders = nativeNewRenders()

  if typeface.isNil or fpsFont.isNil or app.isNil or renders.isNil:
    quit("Failed to initialize native FigDraw objects", 1)

  nativeSiwinFirstStep(app)
  var
    appRunning = true
    frames = 0
    fpsFrames = 0
    fpsStart = epochTime()
    buildMicros = 0.0
    renderMicros = 0.0
    fpsText = "0.0 FPS"

  try:
    while nativeSiwinOpened(app) and appRunning:
      nativeSiwinRefreshUiScale(app)
      inc frames
      inc fpsFrames

      let
        size = nativeSiwinWindowSize(app)
        width = size.w.float32
        height = size.h.float32
        buildStart = getMonoTime()

      buildRenderTree(renders, width, height, frames)
      buildMicros += float((getMonoTime() - buildStart).inMicroseconds)

      let
        hud = Fig(
          kind: nkRectangle,
          screenBox: Rect(x: width - 192, y: 12, w: 180, h: 34),
          fill: fill(rgba(0, 0, 0, 155)),
          corners: [8'u16, 8'u16, 8'u16, 8'u16],
        )
        layout = nativeTypesetText(
          160,
          22,
          fpsFont,
          fpsText,
          hAlign = 2,
          vAlign = 1,
          minContent = false,
          wrapText = false,
        )
      discard nativeAddRoot(renders, 0, hud)

      if not layout.isNil:
        var text = nativeNewTextFig(width - 182, 18, 160, 22)
        text.fill = fill(rgba(0, 0, 0, 0))
        nativeSetFigTextLayout(text, layout)
        discard nativeAddRoot(renders, 0, text)

      let renderStart = getMonoTime()
      nativeRenderSiwinFrame(app, renders, width, height)
      renderMicros += float((getMonoTime() - renderStart).inMicroseconds)
      nativeSiwinRedraw(app)
      nativeSiwinStep(app)

      let elapsed = epochTime() - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        fpsText = fmt"{fps:0.1f} FPS"
        echo "fps: ",
          fps,
          " | elems: ",
          nativeLayerNodeCount(renders, 0),
          " | build avg(us): ",
          buildMicros / fpsFrames.float,
          " | render avg(us): ",
          renderMicros / fpsFrames.float
        fpsFrames = 0
        fpsStart = epochTime()
        buildMicros = 0
        renderMicros = 0

      when RunOnce:
        appRunning = frames < 1

      when not NoSleep:
        if appRunning:
          sleep(16)
  finally:
    nativeSiwinClose(app)
