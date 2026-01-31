when defined(emscripten):
  import std/[times, monotimes, strformat]
else:
  import std/[os, times, monotimes, strformat]

import std/math
import chroma
import pkg/pixie as pix
import pkg/sdfy
import pkg/sdfy/msdfgenSvg

const UseMetalBackend = defined(macosx) and defined(feature.figdraw.metal)

when defined(useWindex):
  import windex
else:
  import figdraw/windyshim

import figdraw/commons
import figdraw/fignodes
import figdraw/renderer as glrenderer

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

proc centeredRect(center, size: Vec2): Rect =
  rect(center.x - size.x / 2.0'f32, center.y - size.y / 2.0'f32, size.x, size.y)

proc addLabel(
    list: var RenderList,
    parentIdx: FigIdx,
    font: UiFont,
    windowW: float32,
    r: Rect,
    text: string,
) =
  let labelH = 28.0'f32
  let labelMargin = 8.0'f32
  let layout = typeset(
    rect(0, 0, max(1.0'f32, windowW), labelH),
    [(font, text)],
    hAlign = Left,
    vAlign = Middle,
    minContent = true,
    wrap = false,
  )
  let padX = 10.0'f32
  let desiredW = ceil(layout.bounding.w + padX * 2.0'f32)
  let maxW = max(r.w, windowW - 24.0'f32)
  let labelW = min(max(r.w, desiredW), maxW)
  let labelRect = rect(
    (r.x + r.w / 2.0'f32) - labelW / 2.0'f32,
    max(0.0'f32, r.y - labelH - labelMargin),
    labelW,
    labelH,
  )

  discard list.addChild(parentIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: labelRect,
    fill: rgba(0, 0, 0, 155).color,
    corners: [8.0'f32, 8.0, 8.0, 8.0],
  ))

  discard list.addChild(parentIdx, Fig(
    kind: nkText,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: labelRect,
    fill: rgba(255, 255, 255, 245).color,
    textLayout: typeset(
      rect(0, 0, labelRect.w, labelRect.h),
      [(font, text)],
      hAlign = Center,
      vAlign = Middle,
      minContent = false,
      wrap = false,
    ),
  ))

proc setupWindow(frame: AppFrame, window: Window) =
  when not defined(emscripten):
    if frame.windowInfo.fullscreen:
      window.fullscreen = frame.windowInfo.fullscreen
    else:
      window.size = ivec2(frame.windowInfo.box.wh.scaled())

    window.visible = true
  when not UseMetalBackend:
    window.makeContextCurrent()

proc newWindyWindow(frame: AppFrame): Window =
  let window = when defined(emscripten):
      newWindow("FigDraw", ivec2(0, 0), visible = false)
    else:
      newWindow("FigDraw", ivec2(1280, 800), visible = false)
  when defined(emscripten):
    setupWindow(frame, window)
    when not UseMetalBackend:
      startOpenGL(openglVersion)
  else:
    when not UseMetalBackend:
      startOpenGL(openglVersion)
    setupWindow(frame, window)
  result = window

proc getWindowInfo(window: Window): WindowInfo =
  app.requestedFrame.inc
  result.minimized = window.minimized()
  result.pixelRatio = window.contentScale()
  let size = window.size()
  result.box.w = size.x.float32.descaled()
  result.box.h = size.y.float32.descaled()

proc makeRenderTree*(
    w, h: float32,
    pxRange: float32,
    t: float32,
    labelFont: UiFont,
): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(30, 30, 30, 255).color,
  ))

  let margin = 40.0'f32
  let innerW = max(0.0'f32, w - margin * 2.0'f32)
  let innerH = max(0.0'f32, h - margin * 2.0'f32)
  let panelRect = rect(margin, margin, innerW, innerH)

  let gap = 28.0'f32
  let shadowOffset = vec2(18.0'f32, 18.0'f32)

  let leftW = innerW * 0.58'f32
  let rightW = innerW - leftW
  let leftRect = rect(panelRect.x, panelRect.y, leftW, innerH)
  let rightRect = rect(panelRect.x + leftW, panelRect.y, rightW, innerH)

  let bigBase = min(leftRect.w, leftRect.h) * 0.82'f32
  let bigBaseSize = vec2(bigBase, bigBase)
  let bigCenter = leftRect.xy + leftRect.wh / 2.0'f32
  let bigScale = 0.85'f32 + 0.20'f32 * (0.5'f32 + 0.5'f32 * sin(t * 1.6'f32))
  let bigSize = bigBaseSize * bigScale
  let bigRotation = t * 45.0'f32

  let smallBase = min((rightRect.w - gap) / 2.0'f32, rightRect.h * 0.45'f32)
  let smallBaseSize = vec2(smallBase, smallBase)
  let smallRowY = rightRect.y + smallBase / 2.0'f32 + rightRect.h * 0.12'f32
  let smallLeftCenter = vec2(rightRect.x + smallBase / 2.0'f32, smallRowY)
  let smallRightCenter =
    vec2(rightRect.x + smallBase * 1.5'f32 + gap, smallRowY)
  let smallScaleA = 0.80'f32 + 0.25'f32 * (0.5'f32 + 0.5'f32 * sin(t * 2.3'f32))
  let smallScaleB =
    0.80'f32 + 0.25'f32 * (0.5'f32 + 0.5'f32 * sin(t * 2.3'f32 + PI.float32))
  let smallScaleC =
    0.80'f32 + 0.25'f32 * (0.5'f32 + 0.5'f32 * sin(t * 2.3'f32 + PI.float32 * 0.5'f32))
  let smallRotationA = -t * 90.0'f32
  let smallRotationB = t * 75.0'f32
  let smallRotationC = -t * 60.0'f32

  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: panelRect,
    fill: rgba(80, 80, 80, 255).color,
    corners: [16.0'f32, 16.0, 16.0, 16.0],
  ))

  ## MSDF star: shadow via MTSDF alpha, then solid fill via MSDF median.
  list.addChild(rootIdx, Fig(
    kind: nkMtsdfImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: centeredRect(bigCenter + shadowOffset, bigSize),
    rotation: bigRotation,
    mtsdfImage: MsdfImageStyle(
      color: rgba(0, 0, 0, 140).color,
      id: imgId("star-mtsdf"),
      pxRange: pxRange,
      sdThreshold: 0.5'f32,
    ),
  ))
  list.addChild(rootIdx, Fig(
    kind: nkMsdfImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: centeredRect(bigCenter, bigSize),
    rotation: bigRotation,
    msdfImage: MsdfImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-msdf"),
      pxRange: pxRange,
      sdThreshold: 0.5'f32,
    ),
  ))

  ## Side-by-side comparison: same bitmap, different render mode.
  let msdfRect = centeredRect(smallLeftCenter, smallBaseSize * smallScaleA)
  list.addChild(rootIdx, Fig(
    kind: nkMsdfImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: msdfRect,
    rotation: smallRotationA,
    msdfImage: MsdfImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-msdf"),
      pxRange: pxRange,
      sdThreshold: 0.5'f32,
    ),
  ))
  list.addLabel(rootIdx, labelFont, w, msdfRect, "MSDF (median)")

  let mtsdfRect = centeredRect(smallRightCenter, smallBaseSize * smallScaleB)
  list.addChild(rootIdx, Fig(
    kind: nkMtsdfImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: mtsdfRect,
    rotation: smallRotationB,
    mtsdfImage: MsdfImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-mtsdf"),
      pxRange: pxRange,
      sdThreshold: 0.5'f32,
    ),
  ))
  list.addLabel(rootIdx, labelFont, w, mtsdfRect, "MTSDF (alpha)")

  ## Bitmap comparison: a normal 32x32 RGBA image rendered from the MSDF field.
  let bitmapCenter =
    vec2(rightRect.x + rightRect.w / 2.0'f32, rightRect.y + rightRect.h * 0.78'f32)
  let bitmapRect = centeredRect(bitmapCenter, smallBaseSize * smallScaleC)
  list.addChild(rootIdx, Fig(
    kind: nkImage,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: bitmapRect,
    rotation: smallRotationC,
    image: ImageStyle(
      color: rgba(255, 215, 0, 255).color,
      id: imgId("star-bitmap"),
    ),
  ))
  list.addLabel(rootIdx, labelFont, w, bitmapRect, "Bitmap (renderMsdf 32x32)")

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

when isMainModule:
  when defined(emscripten):
    setFigDataDir("/data")
  else:
    setFigDataDir(getCurrentDir() / "data")

  let svgPath = figDataDir() / "Yellow_Star_with_rounded_edges.svg"
  let (starPath, elementCount) = loadSvgPath(svgPath)
  doAssert elementCount > 0

  let fieldSize = 32
  let pxRange = 4.0
  let starMsdf = generateMsdfPath(starPath, fieldSize, fieldSize, pxRange)
  let starMtsdf = generateMtsdfPath(starPath, fieldSize, fieldSize, pxRange)
  let renderPxRange = (starMsdf.range * starMsdf.scale).float32

  loadImage(imgId("star-msdf"), starMsdf.image)
  loadImage(imgId("star-mtsdf"), starMtsdf.image)

  let rendered = renderMsdf(starMsdf)
  let bitmap = pix.newImage(fieldSize, fieldSize)
  for i in 0 ..< bitmap.data.len:
    let v = rendered.data[i].r
    bitmap.data[i] = pix.rgba(255'u8, 255'u8, 255'u8, v).rgbx()
  loadImage(imgId("star-bitmap"), bitmap)

  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0
  app.pixelScale = 1.0

  let typefaceId = getTypefaceImpl("Ubuntu.ttf")
  let labelFont = UiFont(typefaceId: typefaceId, size: 18.0'f32,
      lineHeightScale: 1.0)
  let fpsFont = UiFont(typefaceId: typefaceId, size: 18.0'f32,
      lineHeightScale: 1.0)
  var fpsText = "0.0 FPS"

  var frame = AppFrame(
    windowTitle: "figdraw: OpenGL + Windy MSDF/MTSDF",
  )
  frame.windowInfo = WindowInfo(
    box: rect(0, 0, 1024, 640),
    running: true,
    focused: true,
    minimized: false,
    fullscreen: false,
    pixelRatio: 1.0,
  )

  var frames = 0
  var fpsFrames = 0
  var fpsStart = epochTime()
  let window = newWindyWindow(frame)
  let animStart = epochTime()

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = 2048,
    pixelScale = app.pixelScale,
  )

  when UseMetalBackend:
    let metalHandle = attachMetalLayer(window, renderer.ctx.metalDevice())
    renderer.ctx.presentLayer = metalHandle.layer

  var makeRenderTreeMsSum = 0.0
  var renderFrameMsSum = 0.0
  var lastElementCount = 0

  when UseMetalBackend:
    proc updateMetalLayer() =
      metalHandle.updateMetalLayer(window)

  proc redraw() =
    inc frames
    inc fpsFrames

    when UseMetalBackend:
      updateMetalLayer()

    let winInfo = window.getWindowInfo()
    let t = (epochTime() - animStart).float32

    let t0 = getMonoTime()
    var renders = makeRenderTree(
      float32(winInfo.box.w),
      float32(winInfo.box.h),
      renderPxRange,
      t,
      labelFont,
    )
    makeRenderTreeMsSum += float((getMonoTime() - t0).inMilliseconds)
    lastElementCount = renders.layers[0.ZLevel].nodes.len

    let hudMargin = 12.0'f32
    let hudW = 180.0'f32
    let hudH = 34.0'f32
    let hudRect = rect(
      winInfo.box.w.float32 - hudW - hudMargin,
      hudMargin,
      hudW,
      hudH,
    )

    discard renders.layers[0.ZLevel].addRoot(Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: hudRect,
      fill: rgba(0, 0, 0, 155).color,
      corners: [8.0'f32, 8.0, 8.0, 8.0],
    ))

    let hudTextPadX = 10.0'f32
    let hudTextPadY = 6.0'f32
    let hudTextRect = rect(
      hudRect.x + hudTextPadX,
      hudRect.y + hudTextPadY,
      hudRect.w - hudTextPadX * 2,
      hudRect.h - hudTextPadY * 2,
    )

    let fpsLayout = typeset(
      rect(0, 0, hudTextRect.w, hudTextRect.h),
      [(fpsFont, fpsText)],
      hAlign = Right,
      vAlign = Middle,
      minContent = false,
      wrap = false,
    )

    discard renders.layers[0.ZLevel].addRoot(Fig(
      kind: nkText,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: hudTextRect,
      fill: rgba(255, 255, 255, 245).color,
      textLayout: fpsLayout,
    ))

    let t1 = getMonoTime()
    renderer.renderFrame(renders, winInfo.box.wh.scaled())
    renderFrameMsSum += float((getMonoTime() - t1).inMilliseconds)

    when not UseMetalBackend:
      window.swapBuffers()

  window.onCloseRequest = proc() =
    app.running = false
  window.onResize = proc() =
    redraw()

  try:
    while app.running:
      pollEvents()
      redraw()

      let now = epochTime()
      let elapsed = now - fpsStart
      if elapsed >= 1.0:
        let fps = fpsFrames.float / elapsed
        fpsText = fmt"{fps:0.1f} FPS"
        let avgMake = makeRenderTreeMsSum / max(1, fpsFrames).float
        let avgRender = renderFrameMsSum / max(1, fpsFrames).float
        fpsFrames = 0
        fpsStart = now
        makeRenderTreeMsSum = 0.0
        renderFrameMsSum = 0.0
      if RunOnce and frames >= 1:
        app.running = false
  finally:
    when not defined(emscripten):
      window.close()
