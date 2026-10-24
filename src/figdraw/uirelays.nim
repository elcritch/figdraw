## Present software-rendered FigDraw scenes through an installed uirelays driver.
##
## Initialize the uirelays driver and window first. This module imports only the
## platform-independent relays, so the application owns window/event lifetime.
## Use uirelays' native driver or its FigDraw + siwin / Windy driver. The latter
## retains its regular GPU renderer, avoiding recursive software presentation.
## Call uirelays `refresh()` after rendering and after any native text overlays.

import pkg/[chroma, pixie]
from pkg/uirelays/screen as relayScreen import nil
from pkg/uirelays/coords as relayCoords import nil
import ./[commons, figrender]
import ./software/context

export context

proc presentUirelaysImage*(
    image: Image,
    background = rgba(255, 255, 255, 255),
    x = 0,
    y = 0,
    width = 0,
    height = 0,
): bool =
  ## Draws the source into a destination in driver coordinates. Use logical
  ## width/height when the source contains multiple device pixels per point.
  ## The default destination matches the image's dimensions. Transparent pixels are
  ## composited against an opaque background because the relay ignores alpha.
  ## Returns false if the installed driver cannot accept an in-memory image.
  ## Presentation must run on the thread that owns the uirelays window.
  if image.isNil or background.a != 255:
    raise newException(ValueError, "Presentation needs an image and opaque background")
  var pixels = newSeq[uint32](image.data.len)
  for i, pixel in image.data:
    let
      inverse = 255'u32 - pixel.a.uint32
      r = pixel.r.uint32 + (background.r.uint32 * inverse + 127) div 255
      g = pixel.g.uint32 + (background.g.uint32 * inverse + 127) div 255
      b = pixel.b.uint32 + (background.b.uint32 * inverse + 127) div 255
    pixels[i] = (r shl 16) or (g shl 8) or b
  relayScreen.drawRGBA(
    cast[ptr UncheckedArray[uint32]](addr pixels[0]),
    image.width,
    image.height,
    relayCoords.rect(
      x,
      y,
      if width > 0: width else: image.width,
      if height > 0: height else: image.height,
    ),
  )

proc configureUirelaysScale*(layout: relayScreen.ScreenLayout): Vec2 =
  ## Sets FigDraw's raster/UI scale and returns the logical scene size.
  ## Call before building layouts and after a window size or density change.
  ## The raster covers the backing pixels; native uirelays drawing keeps its
  ## usual driver coordinates and applies its own density scaling.
  let
    density = max(1, max(layout.scaleX, layout.scaleY)).float32
    uiScale =
      if layout.uiScale > 0:
        layout.uiScale.float32 / 100'f32
      else:
        1'f32
  setFigUiScale(density * uiScale)
  vec2(layout.width.float32, layout.height.float32) / uiScale

proc newUirelaysContext*(
    background = rgba(255, 255, 255, 255),
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): SoftwareContext =
  ## Creates a software context which blits at endFrame. Initialize a uirelays
  ## window before the first frame. A rejected blit raises ValueError.
  if background.a != 255:
    raise newException(ValueError, "Presentation background must be opaque")
  newSoftwareContext(
    workers = workers,
    parallelThreshold = parallelThreshold,
    presenter = proc(image: Image) =
      let layout = relayScreen.getWindowLayout()
      if not presentUirelaysImage(
        image, background, width = layout.width, height = layout.height
      ):
        raise newException(ValueError, "The uirelays driver cannot present RGBA pixels")
    ,
  )

proc newUirelaysRenderer*(
    background = rgba(255, 255, 255, 255),
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): FigRenderer[NoRendererBackendState] =
  ## Uses the normal FigDraw scene/glyph APIs and presents via uirelays.
  let layout = relayScreen.getWindowLayout()
  if layout.width > 0 and layout.height > 0:
    discard configureUirelaysScale(layout)
  newFigRenderer(newUirelaysContext(background, workers, parallelThreshold))
