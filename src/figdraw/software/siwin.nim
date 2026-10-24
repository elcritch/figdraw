## Direct presentation to Siwin software windows; no GPU context or upload.
## Render and present inside Siwin's onRender callback on the owning thread.

import std/math
import pkg/[chroma, pixie, vmath]
import pkg/siwin/window as siWindow
from pkg/siwin/colorutils import PixelBuffer, PixelBufferFormat
import ../[commons, figrender]
import ./context

export context

proc copyPixels(image: Image, buffer: PixelBuffer) =
  if buffer.format == PixelBufferFormat.rgbx_32bit:
    copyMem(buffer.data, image.data[0].addr, image.data.len * sizeof(ColorRGBX))
    return
  let output = cast[ptr UncheckedArray[array[4, uint8]]](buffer.data)
  for i, pixel in image.data:
    case buffer.format
    of PixelBufferFormat.rgbx_32bit:
      discard
    of PixelBufferFormat.bgrx_32bit:
      output[i] = [pixel.b, pixel.g, pixel.r, pixel.a]
    of PixelBufferFormat.xrgb_32bit:
      output[i] = [pixel.a, pixel.r, pixel.g, pixel.b]
    of PixelBufferFormat.bgra_32bit:
      let straight = pixel.rgba()
      output[i] = [straight.b, straight.g, straight.r, straight.a]
    of PixelBufferFormat.rgba_32bit:
      let straight = pixel.rgba()
      output[i] = [straight.r, straight.g, straight.b, straight.a]
    of PixelBufferFormat.bgru_32bit:
      output[i] = [pixel.b, pixel.g, pixel.r, 255'u8]
    of PixelBufferFormat.urgb_32bit:
      output[i] = [255'u8, pixel.r, pixel.g, pixel.b]
    of PixelBufferFormat.rgbu_32bit:
      output[i] = [pixel.r, pixel.g, pixel.b, 255'u8]

proc present(
    image: Image,
    buffer: PixelBuffer,
    scratch: var Image,
    background: ColorRGBA,
    opaque: bool,
) =
  if image.isNil or buffer.data.isNil or buffer.size.x <= 0 or buffer.size.y <= 0:
    raise newException(
      ValueError, "Presentation needs an image and a valid Siwin pixel buffer"
    )
  if image.width != buffer.size.x or image.height != buffer.size.y:
    raise
      newException(ValueError, "Render at the Siwin pixel buffer's backing resolution")
  if background.a != 255:
    raise newException(ValueError, "Software presentation background must be opaque")
  let unusedAlpha =
    buffer.format in {
      PixelBufferFormat.bgru_32bit, PixelBufferFormat.urgb_32bit,
      PixelBufferFormat.rgbu_32bit,
    }
  if opaque or unusedAlpha:
    if scratch.isNil or scratch.width != image.width or scratch.height != image.height:
      scratch = newImage(image.width, image.height)
    scratch.fill(background)
    scratch.draw(image)
    copyPixels(scratch, buffer)
  else:
    copyPixels(image, buffer)

proc writeSiwinPixelBuffer*(
    image: Image,
    buffer: PixelBuffer,
    background = rgba(255, 255, 255, 255),
    opaque = false,
) =
  ## Copy without resampling. RGBA/BGRA straight and premultiplied formats are
  ## supported. Formats without alpha always composite over `background` using
  ## Pixie; `opaque=true` also flattens formats that have alpha. Input is borrowed
  ## and never modified. The destination buffer is valid only during onRender.
  var scratch: Image
  present(image, buffer, scratch, background, opaque)

proc configureSiwinSoftwareScale*(window: siWindow.Window): Vec2 =
  ## Call inside onRender before laying out/rendering the frame. Return the
  ## logical frame size for the current backing buffer and update FigDraw scale.
  if window.isNil:
    raise newException(ValueError, "Software presentation needs a Siwin window")
  let buffer = window.pixelBuffer()
  if buffer.data.isNil or buffer.size.x <= 0 or buffer.size.y <= 0:
    return vec2(0)
  let density = window.uiScale()
  if classify(density) in {fcNan, fcInf, fcNegInf} or density <= 0:
    raise newException(ValueError, "Siwin UI scale must be finite and positive")
  result = vec2(buffer.size.x.float32, buffer.size.y.float32) / density
  if classify(result.x) in {fcNan, fcInf, fcNegInf} or
      classify(result.y) in {fcNan, fcInf, fcNegInf}:
    raise newException(ValueError, "Siwin scale produces an invalid logical frame size")
  setFigUiScale(density)
  # Avoid an extra framebuffer column/row when division and multiplication
  # round a fractional-scale length just above the integer backing size.
  for axis in 0 ..< 2:
    let pixels = if axis == 0: buffer.size.x else: buffer.size.y
    if ceil(result[axis] * density).int > pixels:
      result[axis] = cast[float32](cast[uint32](result[axis]) - 1'u32)

proc newSiwinSoftwareContext*(
    window: siWindow.Window,
    background = rgba(255, 255, 255, 255),
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): SoftwareContext =
  ## Attach CPU presentation to an existing Siwin software-rendering window.
  ## Render inside onRender; Siwin presents after the callback returns. The
  ## window buffer is reacquired each frame, including after resize. A reusable
  ## Pixie image composites frames for opaque windows. No GPU resources are used.
  if window.isNil or background.a != 255:
    raise newException(ValueError, "Presentation needs a window and opaque background")
  var scratch: Image
  newSoftwareContext(
    workers = workers,
    parallelThreshold = parallelThreshold,
    presenter = proc(image: Image) =
      present(
        image, window.pixelBuffer(), scratch, background, not window.transparent()
      ),
  )

proc newSiwinSoftwareRenderer*(
    window: siWindow.Window,
    background = rgba(255, 255, 255, 255),
    workers: Natural = 0,
    parallelThreshold: Positive = 262_144,
): FigRenderer[NoRendererBackendState] =
  ## Keep Siwin window/events and FigDraw scenes, with CPU rendering/presentation.
  newFigRenderer(
    newSiwinSoftwareContext(window, background, workers, parallelThreshold)
  )
