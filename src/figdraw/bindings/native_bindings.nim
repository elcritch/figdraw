## Native dynamic-library producer entry point and ABI-specific adapters.

import pkg/pixie as pixie

import figdraw/commons
import figdraw/figrender
import figdraw/windowing/siwinshim

type SiwinRenderer* = FigRenderer[SiwinRenderBackend]

# Materialize the concrete routines for Binny's semantic-symbol discovery.
# This private instantiation anchor is never called or exported.
proc instantiateNativeExports(renderer: SiwinRenderer, image: pixie.Image) {.used.} =
  discard renderer.backendKind()
  discard renderer.backendName()
  renderer.setTextLcdFiltering(renderer.textLcdFiltering())
  renderer.setTextSubpixelPositioning(renderer.textSubpixelPositioning())
  renderer.setTextSubpixelGlyphVariants(renderer.textSubpixelGlyphVariants())
  discard backendSupportsDedicatedRenderThread(renderer.backendKind())
  discard renderer.supportsDedicatedRenderThread()
  # Keep the concrete dedicated-render routine in the producer ABI even
  # though this anchor is never called by the library entry point.
  renderer.useDedicatedRenderThread()
  pixie.`[]=`(image, 0, 0, default(ColorRGBA))
  pixie.fill(image, default(ColorRGBA))

proc newFigSiwinApp*(
    window: Window, atlasSize: int, pixelScale: float32
): SiwinRenderer =
  ## Attaches FigDraw's renderer to a caller-created Siwin window.
  when UseVulkanBackend:
    result = newFigRenderer(atlasSize, SiwinRenderBackend(), pixelScale)
  else:
    result = newFigRenderer(atlasSize, SiwinRenderBackend(window: window), pixelScale)
  result.setupBackend(window)
  discard window.configureUiScale()
