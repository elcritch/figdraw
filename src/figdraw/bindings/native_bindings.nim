## Native dynamic-library producer entry point and ABI-specific adapters.

import vmath
import pkg/pixie as pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender
import figdraw/windowing/siwinshim

type
  SiwinRenderer* = FigRenderer[SiwinRenderBackend]

  NativeSiwinApp* = ref object
    ## Groups a managed renderer with the app's automatic UI-scale policy.
    renderer*: SiwinRenderer
    autoScale: bool

# Materialize the concrete routines for Binny's semantic-symbol discovery.
# This private instantiation anchor is never called or exported.
proc instantiateRendererExports(renderer: SiwinRenderer) {.used.} =
  discard renderer.backendKind()
  discard renderer.backendName()
  renderer.setTextLcdFiltering(renderer.textLcdFiltering())
  renderer.setTextSubpixelPositioning(renderer.textSubpixelPositioning())
  renderer.setTextSubpixelGlyphVariants(renderer.textSubpixelGlyphVariants())

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
  NativeSiwinApp(renderer: renderer, autoScale: window.configureUiScale())

proc renderFrame*(
    app: NativeSiwinApp,
    renders: var Renders,
    width, height: float32,
    clearMain: bool,
    clearR, clearG, clearB, clearA: float32,
) =
  app.renderer.backendState.window.refreshUiScale(app.autoScale)
  app.renderer.beginFrame()
  app.renderer.renderFrame(
    renders,
    vec2(width, height),
    clearMain = clearMain,
    clearColor = color(clearR, clearG, clearB, clearA),
  )
  app.renderer.endFrame()
