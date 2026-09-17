## Native dynamic-library producer entry point and ABI-specific adapters.

import pkg/pixie as pixie

import figdraw/commons
import figdraw/common/fonttypes
import figdraw/figrender
import figdraw/windowing/siwinshim
from figdraw/common/typefaces import nil
from figdraw/common/imgutils import nil

type SiwinRenderer* = FigRenderer[SiwinRenderBackend]

type
  FontRef* = object
    ## Producer-owned font reference with compiler-generated ownership hooks.
    value: typefaces.FontRef

  ImageMessageSubscription* = object
    ## Keeps subscription channels and their destruction inside the producer.
    value: imgutils.ImageMessageSubscription

proc newNativeFontRef*(font: sink FigFont): FontRef =
  FontRef(value: typefaces.fontRef(font))

proc font*(handle: FontRef): FigFont =
  ## Returns the font value retained by this handle.
  handle.value.font

proc fontId*(handle: FontRef): FontId =
  handle.value.fontId

proc isNil*(handle: FontRef): bool =
  handle.value.isNil

proc sameFontRef*(a, b: FontRef): bool =
  typefaces.sameFontRef(a.value, b.value)

proc fs*(handle: FontRef, color: Fill): FontStyle =
  fs(handle.value, color)

proc fsp*(handle: FontRef, color: Fill, text: string): (FontStyle, string) =
  fsp(handle.value, color, text)

proc span*(handle: FontRef, color: Fill, text: string): (FontStyle, string) =
  span(handle.value, color, text)

proc clearFontGlyphs*(handle: FontRef) =
  clearFontGlyphs(handle.value)

proc newImageMessageSubscription*(): ImageMessageSubscription =
  ImageMessageSubscription(value: imgutils.newImageMessageSubscription())

proc tryRecvImageMsg*(handle: ImageMessageSubscription, msg: var ImageMsg): bool =
  imgutils.tryRecvImageMsg(handle.value, msg)

proc tryRecvImageMsg*(msg: var ImageMsg): bool =
  imgutils.tryRecvImageMsg(msg)

proc replayImageMessages*(handle: ImageMessageSubscription) =
  imgutils.replayImageMessages(handle.value)

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
