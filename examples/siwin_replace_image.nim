import std/[math, os, strformat, times]

import pkg/pixie as pix

when defined(useNativeDynlib):
  import figdraw/dynlib
else:
  import figdraw
  import figdraw/windowing/siwinshim

const
  RunOnce {.booldefine: "figdraw.runOnce".}: bool = false
  CanvasWidth = 512
  CanvasHeight = 320

proc makeCanvasFrame(t: float32): pix.Image =
  ## Draw one frame with Pixie. Each returned image has the same dimensions, so
  ## FigDraw can update its existing atlas slot instead of allocating a new one.
  result = pix.newImage(CanvasWidth, CanvasHeight)
  let ctx = pix.newContext(result)

  ctx.fillStyle = pix.rgba(10, 17, 35, 255)
  ctx.fillRect(0, 0, CanvasWidth.float32, CanvasHeight.float32)

  ctx.strokeStyle = pix.rgba(91, 126, 176, 45)
  ctx.lineWidth = 1
  for x in countup(0, CanvasWidth, 32):
    ctx.strokeSegment(
      pix.segment(pix.vec2(x.float32, 0), pix.vec2(x.float32, CanvasHeight.float32))
    )
  for y in countup(0, CanvasHeight, 32):
    ctx.strokeSegment(
      pix.segment(pix.vec2(0, y.float32), pix.vec2(CanvasWidth.float32, y.float32))
    )

  let
    centerY = CanvasHeight.float32 * 0.52'f32
    waveWidth = CanvasWidth.float32

  ctx.beginPath()
  for x in 0 .. CanvasWidth:
    let
      phase = x.float32 / waveWidth * PI.float32 * 4.0'f32 + t * 3.2'f32
      y = centerY + sin(phase) * 48.0'f32 + sin(phase * 0.43'f32 - t) * 16.0'f32
    if x == 0:
      ctx.moveTo(x.float32, y)
    else:
      ctx.lineTo(x.float32, y)
  ctx.strokeStyle = pix.rgba(73, 224, 255, 255)
  ctx.lineWidth = 5
  ctx.stroke()

  let
    markerX = (t * 95.0'f32) mod waveWidth
    markerPhase = markerX / waveWidth * PI.float32 * 4.0'f32 + t * 3.2'f32
    markerY =
      centerY + sin(markerPhase) * 48.0'f32 + sin(markerPhase * 0.43'f32 - t) * 16.0'f32
  ctx.fillStyle = pix.rgba(255, 92, 138, 80)
  ctx.fillCircle(pix.circle(pix.vec2(markerX, markerY), 22.0'f32))
  ctx.fillStyle = pix.rgba(255, 125, 166, 255)
  ctx.fillCircle(pix.circle(pix.vec2(markerX, markerY), 9.0'f32))

  let
    orbitCenter = pix.vec2(CanvasWidth.float32 * 0.80'f32, 72.0'f32)
    orbitPos = orbitCenter + pix.vec2(cos(t * 1.7'f32), sin(t * 1.7'f32)) * 34.0'f32
  ctx.strokeStyle = pix.rgba(170, 138, 255, 100)
  ctx.lineWidth = 2
  ctx.strokeCircle(pix.circle(orbitCenter, 34.0'f32))
  ctx.fillStyle = pix.rgba(255, 207, 91, 255)
  ctx.fillCircle(pix.circle(orbitPos, 8.0'f32))

  let progress = (0.5'f32 + 0.5'f32 * sin(t * 1.4'f32)) * 180.0'f32
  ctx.fillStyle = pix.rgba(50, 68, 101, 255)
  ctx.fillRoundedRect(pix.rect(24, 278, 180, 12), 6)
  ctx.fillStyle = pix.rgba(133, 104, 255, 255)
  ctx.fillRoundedRect(pix.rect(24, 278, progress, 12), 6)

proc makeRenderTree(
    windowW, windowH: float32, imageId: ImageId, fpsFont: FigFont, fpsText: string
): Renders =
  result = newRenders()
  let z = 0.ZLevel
  discard result.addRoot(
    z,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rect(0, 0, windowW, windowH),
      fill: rgba(20, 24, 36, 255),
    ),
  )

  let
    margin = 56.0'f32
    maxW = max(1.0'f32, windowW - margin * 2.0'f32)
    maxH = max(1.0'f32, windowH - margin * 2.0'f32)
    aspect = CanvasWidth.float32 / CanvasHeight.float32
    imageW = min(maxW, maxH * aspect)
    imageH = imageW / aspect
    imageRect =
      rect((windowW - imageW) / 2.0'f32, (windowH - imageH) / 2.0'f32, imageW, imageH)

  discard result.addRoot(
    z,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox:
        rect(imageRect.x - 8, imageRect.y - 8, imageRect.w + 16, imageRect.h + 16),
      fill: rgba(45, 53, 75, 255),
      corners: [14'u16, 14'u16, 14'u16, 14'u16],
    ),
  )
  discard result.addRoot(
    z,
    Fig(
      kind: nkImage,
      childCount: 0,
      zlevel: z,
      screenBox: imageRect,
      image: imageStyle(imageId),
    ),
  )

  let
    hudRect = rect(windowW - 142.0'f32, 16, 126, 34)
    hudTextRect = rect(hudRect.x + 10, hudRect.y + 5, hudRect.w - 20, hudRect.h - 10)
  discard result.addRoot(
    z,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: hudRect,
      fill: rgba(0, 0, 0, 165),
      corners: [8'u16, 8'u16, 8'u16, 8'u16],
    ),
  )
  discard result.addRoot(
    z,
    Fig(
      kind: nkText,
      childCount: 0,
      zlevel: z,
      screenBox: hudTextRect,
      fill: clearColor,
      textLayout: typeset(
        rect(0, 0, hudTextRect.w, hudTextRect.h),
        [(fs(fpsFont, rgba(255, 255, 255, 245).color), fpsText)],
        hAlign = Right,
        vAlign = Middle,
        minContent = false,
        wrap = false,
      ),
    ),
  )

when isMainModule:
  setFigDataDir(getCurrentDir() / "data")

  let
    liveImageId = imgId("replace-image-live-pixie-canvas")
    typefaceId = loadTypeface("Ubuntu.ttf")
    fpsFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
    windowSize = ivec2(960, 640)
    title = siwinWindowTitle("Siwin replaceImage + Pixie")

  loadImage(liveImageId, makeCanvasFrame(0))

  var appRunning = true
  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
    let appWindow =
      newSiwinWindow(renderer, size = windowSize, fullscreen = false, title = title)
  else:
    let appWindow = newSiwinWindow(size = windowSize, fullscreen = false, title = title)
    let renderer = newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
  let useAutoScale = appWindow.configureUiScale()

  renderer.setupBackend(appWindow)
  appWindow.title = siwinWindowTitle(renderer, appWindow, "Siwin replaceImage + Pixie")

  let animationStart = epochTime()
  var
    frames = 0
    fpsFrames = 0
    fpsStart = animationStart
    fpsText = "0.0 FPS"

  proc redraw() =
    let
      now = epochTime()
      t = (now - animationStart).float32

    inc frames
    inc fpsFrames
    let fpsElapsed = now - fpsStart
    if fpsElapsed >= 1.0:
      fpsText = fmt"{fpsFrames.float / fpsElapsed:0.1f} FPS"
      fpsFrames = 0
      fpsStart = now

    # The ID remains stable. FigDraw replaces the pixels and reuses the atlas
    # slot because every Pixie frame has the same dimensions.
    replaceImage(liveImageId, makeCanvasFrame(t))

    renderer.beginFrame()
    let logicalSize = appWindow.logicalSize()
    var renders =
      makeRenderTree(logicalSize.x, logicalSize.y, liveImageId, fpsFont, fpsText)
    renderer.renderFrame(renders, logicalSize)
    renderer.endFrame()

  appWindow.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      appRunning = false,
    onResize: proc(e: ResizeEvent) =
      appWindow.refreshUiScale(useAutoScale)
      redraw(),
    onKey: proc(e: KeyEvent) =
      if e.pressed and e.key == Key.escape:
        close(e.window)
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  appWindow.firstStep()
  appWindow.refreshUiScale(useAutoScale)

  try:
    while appRunning and appWindow.opened:
      appWindow.redraw()
      appWindow.step()
      if RunOnce and frames >= 1:
        appRunning = false
  finally:
    appWindow.close()
