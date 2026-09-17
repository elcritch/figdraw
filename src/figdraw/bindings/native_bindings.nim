## Native Nim dynamic-library facade generated through Binny.

import std/[options, unicode]
import vmath
import pkg/pixie as pixie
import pkg/pixie/fileformats/png as png
import siwin/colorutils

import figdraw/commons
import figdraw/common/fonttypes as fonttypes
import figdraw/fignodes
import figdraw/figrender
import figdraw/windowing/siwinshim

type
  # Keep a stable ABI name for the stdlib Slice boundary converters.
  IntSlice* = Slice[int]

  # Owns renderer state; Siwin windows and events are exported directly.
  NativeSiwinApp* = object
    raw*: pointer

  SiwinApp = ref object
    renderer: FigRenderer[SiwinRenderBackend]
    autoScale: bool

proc utf8RunesFromRunes*(runes: seq[Rune]): fonttypes.Utf8Runes =
  ## Creates UTF-8-backed storage from a compatibility rune sequence.
  fonttypes.initUtf8Runes(runes)

proc retainRaw[T](raw: pointer) =
  if raw != nil:
    let value {.cursor.} = cast[T](raw)
    GC_ref(value)

proc releaseRaw[T](raw: pointer) =
  if raw != nil:
    let value {.cursor.} = cast[T](raw)
    GC_unref(value)

template defineHandleHooks(HandleType, RefType: typedesc) =
  proc `=destroy`(value: HandleType) =
    releaseRaw[RefType](value.raw)

  proc `=copy`(dest: var HandleType, source: HandleType) =
    if dest.raw != source.raw:
      retainRaw[RefType](source.raw)
      releaseRaw[RefType](dest.raw)
      dest.raw = source.raw

defineHandleHooks(NativeSiwinApp, SiwinApp)

proc wrap(value: SiwinApp): NativeSiwinApp =
  retainRaw[SiwinApp](cast[pointer](value))
  result.raw = cast[pointer](value)

template siwinApp(value: NativeSiwinApp): SiwinApp =
  cast[SiwinApp](value.raw)

proc newPixieImage*(width, height: int): pixie.Image =
  pixie.newImage(width, height)

proc readPixieImage*(filePath: string): pixie.Image =
  pixie.readImage(filePath)

proc decodePixieImage*(data: string): pixie.Image =
  pixie.decodeImage(data)

proc encodePng*(value: pixie.Image): string =
  png.encodePng(value)

proc writePixieImage*(value: pixie.Image, filePath: string) =
  value.writeFile(filePath)

proc copyImage*(value: pixie.Image): pixie.Image =
  value.copy()

proc imageWidth*(value: pixie.Image): int =
  value.width

proc imageHeight*(value: pixie.Image): int =
  value.height

proc imagePixel*(value: pixie.Image, x, y: int): ColorRGBA =
  value[x, y].rgba()

proc setImagePixel*(value: pixie.Image, x, y: int, color: ColorRGBA) =
  value[x, y] = color

proc fillImage*(value: pixie.Image, color: ColorRGBA) =
  value.fill(color)

proc putFigImage*(id: ImageId, value: pixie.Image) =
  loadImage(id, value)

proc replaceFigImage*(id: ImageId, value: pixie.Image) =
  replaceImage(id, value)

proc newFigSiwinApp*(
    window: Window, atlasSize: int, pixelScale: float32
): NativeSiwinApp =
  ## Attaches FigDraw's renderer to a caller-created Siwin window.
  when UseVulkanBackend:
    let renderer = newFigRenderer(atlasSize, SiwinRenderBackend(), pixelScale)
  else:
    let renderer =
      newFigRenderer(atlasSize, SiwinRenderBackend(window: window), pixelScale)
  renderer.setupBackend(window)
  wrap(SiwinApp(renderer: renderer, autoScale: window.configureUiScale()))

proc siwinStartInteractiveMove*(window: Window, pos: Vec2) =
  window.startInteractiveMove(some(pos))

proc siwinStartInteractiveResize*(window: Window, edge: Edge, pos: Vec2) =
  window.startInteractiveResize(edge, some(pos))

proc siwinShowWindowMenu*(window: Window, pos: Vec2) =
  window.showWindowMenu(some(pos))

proc siwinSetIcon*(window: Window, value: pixie.Image) =
  let image = value
  if image.isNil or image.data.len == 0:
    window.icon = nil
  else:
    window.icon = PixelBuffer(
      data: image.data[0].addr,
      size: ivec2(image.width.int32, image.height.int32),
      format: rgbx_32bit,
    )

proc siwinBackendName*(appHandle: NativeSiwinApp): string =
  siwinApp(appHandle).renderer.siwinBackendName()

proc siwinBackendKind*(appHandle: NativeSiwinApp): RendererBackendKind =
  siwinApp(appHandle).renderer.backendKind()

proc setTextLcdFiltering*(appHandle: NativeSiwinApp, enabled: bool) =
  siwinApp(appHandle).renderer.setTextLcdFiltering(enabled)

proc textLcdFiltering*(appHandle: NativeSiwinApp): bool =
  siwinApp(appHandle).renderer.textLcdFiltering()

proc setTextSubpixelPositioning*(appHandle: NativeSiwinApp, enabled: bool) =
  siwinApp(appHandle).renderer.setTextSubpixelPositioning(enabled)

proc textSubpixelPositioning*(appHandle: NativeSiwinApp): bool =
  siwinApp(appHandle).renderer.textSubpixelPositioning()

proc setTextSubpixelGlyphVariants*(appHandle: NativeSiwinApp, enabled: bool) =
  siwinApp(appHandle).renderer.setTextSubpixelGlyphVariants(enabled)

proc textSubpixelGlyphVariants*(appHandle: NativeSiwinApp): bool =
  siwinApp(appHandle).renderer.textSubpixelGlyphVariants()

proc renderFrame*(
    appHandle: NativeSiwinApp,
    renders: var Renders,
    width, height: float32,
    clearMain: bool,
    clearR, clearG, clearB, clearA: float32,
) =
  let app = siwinApp(appHandle)
  app.renderer.backendState.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  app.renderer.renderFrame(
    renders,
    vec2(width, height),
    clearMain = clearMain,
    clearColor = color(clearR, clearG, clearB, clearA),
  )
  app.renderer.endFrame()
