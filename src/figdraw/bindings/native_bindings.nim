## Native dynamic-library producer entry point and ABI-specific adapters.

import vmath
import pkg/pixie as pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender
import figdraw/windowing/siwinshim

type
  # Owns renderer state; Siwin windows and events are exported directly.
  NativeSiwinApp* = object
    raw*: pointer

  SiwinApp = ref object
    renderer: FigRenderer[SiwinRenderBackend]
    autoScale: bool

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

proc imagePixel*(value: pixie.Image, x, y: int): ColorRGBA =
  ## Converts Pixie's premultiplied pixel to FigDraw's straight-alpha view.
  value[x, y].rgba()

proc `[]=`*(value: pixie.Image, x, y: int, color: ColorRGBA) =
  ## Instantiates Pixie's generic pixel setter for the shared RGBA type.
  pixie.`[]=`(value, x, y, color)

proc fill*(value: pixie.Image, color: ColorRGBA) =
  ## Instantiates Pixie's generic fill routine for the shared RGBA type.
  pixie.fill(value, color)

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
