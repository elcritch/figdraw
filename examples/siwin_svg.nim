## Interactive SVG viewer: drag to pan, scroll to zoom around the pointer.
## Run: nim r examples/siwin_svg.nim [input.svg] [--size=N] [--adaptive|--fixed] [--raster|--mtsdf]
import std/[math, os, strutils]
import figdraw
import figdraw/windowing
import figdraw/svgs/svg

const RunOnce {.booldefine: "figdraw.runOnce".}: bool = false

const FieldSizes* = [48, 96, 192, 384, 768]

proc nextFieldSize*(current: int, increase: bool): int =
  ## Move to the next preset without wrapping at either end.
  if increase:
    for size in FieldSizes:
      if size > current:
        return size
    max(current, FieldSizes[^1])
  else:
    for i in countdown(FieldSizes.high, 0):
      if FieldSizes[i] < current:
        return FieldSizes[i]
    min(current, FieldSizes[0])

type SvgView* = object
  offset*: Vec2
  zoom*: float32

proc fit*(view: var SvgView, documentSize, windowSize: Vec2) =
  ## Fit the document with a 24-point margin, preserving aspect ratio.
  let available = max(windowSize - vec2(48), vec2(1))
  view.zoom = min(available.x / documentSize.x, available.y / documentSize.y)
  view.offset = (windowSize - documentSize * view.zoom) / 2

proc zoomAt*(view: var SvgView, anchor: Vec2, factor: float32) =
  ## Keep the document point beneath the anchor stationary while zooming.
  let next = clamp(view.zoom * factor, 0.01'f32, 32'f32)
  view.offset = anchor - (anchor - view.offset) * (next / view.zoom)
  view.zoom = next

proc svgScene(resource: SvgMtsdfResource, view: SvgView, size: Vec2): Renders =
  result = newRenders()
  var list: RenderList
  list.addRoot(
    Fig(
      kind: nkRectangle,
      screenBox: rect(0, 0, size.x, size.y),
      fill: fill(rgba(225, 228, 232, 255)),
    )
  )
  let target = rect(
    view.offset.x,
    view.offset.y,
    resource.size.x * view.zoom,
    resource.size.y * view.zoom,
  )
  list.addRoot(
    Fig(kind: nkRectangle, screenBox: target, fill: fill(rgba(255, 255, 255, 255)))
  )
  list.addSvgMtsdf(target, resource)
  result.setLayer(0.ZLevel, list)

when isMainModule:
  var
    input = ""
    fieldSize = DefaultSvgMtsdfLongEdge
    adaptive = true
    renderMode = srmMtsdf
  for arg in commandLineParams():
    if arg.startsWith("--size="):
      try:
        fieldSize = parseInt(arg[7 .. ^1])
      except ValueError:
        quit "Invalid --size; use an integer from 32 to 1024"
      if fieldSize notin 32 .. 1024:
        quit "Invalid --size; use an integer from 32 to 1024"
    elif arg == "--adaptive":
      adaptive = true
    elif arg == "--fixed":
      adaptive = false
    elif arg == "--raster":
      renderMode = srmRaster
    elif arg == "--mtsdf":
      renderMode = srmMtsdf
    elif arg.startsWith("-") or input.len > 0:
      quit "Usage: siwin_svg [input.svg] [--size=N] [--adaptive|--fixed] [--raster|--mtsdf]"
    else:
      input = arg
  if input.len == 0:
    input = currentSourcePath().parentDir.parentDir / "data" / "Ghostscript_Tiger.svg"
  let svgData = readFile(input)
  var resource = newSvgMtsdfResource(
    svgData, longEdge = fieldSize, adaptive = adaptive, renderMode = renderMode
  )
  echo "Drag: pan | Scroll: zoom | [ / ]: field size | A: adaptive/fixed | I: image/MTSDF | R: fit"
  let initialSize = ivec2(900, 800)
  let title = "SVG Viewer - " & input.extractFilename()
  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
    let window =
      newSiwinWindow(renderer, size = initialSize, title = title, vsync = true)
  else:
    let window = newSiwinWindow(size = initialSize, title = title, vsync = true)
    let renderer = newFigRenderer(atlasSize = 2048, backendState = SiwinRenderBackend())
  let autoScale = window.configureUiScale()
  when defined(linux) or defined(bsd):
    if window.siwinDisplayServerName() == "x11" and initialSize != initialSize.scaled():
      window.size = initialSize.scaled()
  renderer.setupBackend(window)

  var
    running = true
    dragging = false
    dirty = true
    lastPointer: Vec2
    lastSize: Vec2
    view = SvgView(zoom: 1)
    scene = newRenders()
    frames = 0

  proc pointerPosition(): Vec2 =
    if window.inputUsesBackingPixels():
      window.mouse.pos.descaled()
    else:
      window.mouse.pos

  proc requestRedraw() =
    dirty = true
    window.redraw()

  proc resetView() =
    view.fit(resource.size, window.logicalSize())
    requestRedraw()

  proc zoom(factor: float32, anchor: Vec2) =
    view.zoomAt(anchor, factor)
    requestRedraw()

  proc setFieldQuality(newSize: int, newAdaptive: bool, newMode: SvgRenderMode) =
    if newSize == fieldSize and newAdaptive == adaptive and newMode == renderMode:
      return
    try:
      # Generate before releasing the old resource so an error leaves the view usable.
      let replacement = newSvgMtsdfResource(
        svgData, longEdge = newSize, adaptive = newAdaptive, renderMode = newMode
      )
      scene = newRenders()
      resource = replacement
      fieldSize = newSize
      adaptive = newAdaptive
      renderMode = newMode
      requestRedraw()
    except SvgMtsdfError as error:
      stderr.writeLine("Unable to rebuild SVG fields: " & error.msg)

  proc redraw() =
    let size = window.logicalSize()
    if size.x <= 0 or size.y <= 0:
      return
    if size != lastSize:
      if lastSize == vec2(0):
        view.fit(resource.size, size)
      else:
        view.offset += (size - lastSize) / 2
      lastSize = size
      dirty = true
    if dirty:
      scene = svgScene(resource, view, size)
      window.title = siwinWindowTitle(
        renderer,
        window,
        title & " | " & formatFloat(view.zoom * 100, ffDecimal, 0) & "% | " &
          (if renderMode == srmRaster: "Image " else: "MTSDF ") & $fieldSize & (
          if renderMode == srmMtsdf: (if adaptive: " adaptive" else: " fixed")
          else: ""
        ) & " | [ ]: size | A: adaptive | I: image | R: fit",
      )
      dirty = false
    renderer.beginFrame()
    renderer.renderFrame(scene, size)
    renderer.endFrame()
    inc frames

  window.eventsHandler = WindowEventsHandler(
    onClose: proc(e: CloseEvent) =
      running = false,
    onResize: proc(e: ResizeEvent) =
      window.refreshUiScale(autoScale)
      requestRedraw(),
    onMouseButton: proc(e: MouseButtonEvent) =
      if e.button == MouseButton.left:
        dragging = e.pressed
        lastPointer = pointerPosition()
    ,
    onMouseMove: proc(e: MouseMoveEvent) =
      let point = pointerPosition()
      if dragging and MouseButton.left in window.mouse.pressed:
        view.offset += point - lastPointer
        requestRedraw()
      else:
        dragging = false
      lastPointer = point,
    onScroll: proc(e: ScrollEvent) =
      # Cocoa reports positive upward deltas; other Siwin backends use negative.
      let direction =
        when defined(macosx):
          e.delta
        else:
          -e.delta
      zoom(exp(clamp(direction.float32 * 0.12'f32, -1'f32, 1'f32)), pointerPosition()),
    onKey: proc(e: KeyEvent) =
      if e.pressed:
        case e.key
        of Key.escape:
          window.close()
        of Key.r, Key.n0, Key.home:
          resetView()
        of Key.lbracket:
          setFieldQuality(nextFieldSize(fieldSize, false), adaptive, renderMode)
        of Key.rbracket:
          setFieldQuality(nextFieldSize(fieldSize, true), adaptive, renderMode)
        of Key.a:
          setFieldQuality(fieldSize, not adaptive, renderMode)
        of Key.i:
          setFieldQuality(
            fieldSize, adaptive, if renderMode == srmMtsdf: srmRaster else: srmMtsdf
          )
        of Key.equal, Key.add:
          zoom(1.2, window.logicalSize() / 2)
        of Key.minus, Key.subtract:
          zoom(1 / 1.2, window.logicalSize() / 2)
        else:
          discard
    ,
    onRender: proc(e: RenderEvent) =
      redraw(),
  )
  window.firstStep()
  window.refreshUiScale(autoScale)
  window.redraw()
  try:
    while running and window.opened:
      window.step()
      if RunOnce and frames > 0:
        break
      sleep(8)
  finally:
    renderer.finishPendingFrames()
    window.close()
