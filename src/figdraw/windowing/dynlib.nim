## Windowing conveniences over the generated native ABI.

import std/options
from pkg/pixie import Image
import pkg/vmath as vmath

import figdraw_native_abi
import figdraw/dynlib

export figdraw_native_abi except
  placeGlyphs, newSiwinWindow, newFigRenderer, drawableDashedRoundedRectBorderOps,
  drawableDottedRoundedRectBorderOps, figDashedRoundedRectBorder, figRoundedRectBorder,
  figDottedRoundedRectBorder, `[]`, Hash, RootObj, MonoTime, getFigFont,
  getTypefaceSource, getTypefaceInfo, typeset, typesetForMeasurement, generateGlyph,
  generateGlyphImages, hash, getContentHash, findSystemTypeface, findSystemFontFile,
  systemDefaultFontNames, FillKind, FillGradientAxis

type
  AtlasUsage* = NativeAtlasUsage

  FigRenderer*[BackendState] = ref object
    atlasSize: int
    pixelScale: float32
    backendState: BackendState
    native: SiwinRenderer
    window: Window
    autoScale: bool

converter toSiwinRenderer*(renderer: FigRenderer[SiwinRenderBackend]): SiwinRenderer =
  ## Exposes the typed renderer for direct native renderer operations.
  renderer.native

converter toCursor*(value: BuiltinCursor): Cursor {.inline.} =
  Cursor(kind: CursorKind.builtin, builtin: value)

converter toOptionalPosition*(value: vmath.Vec2): Option[vmath.Vec2] {.inline.} =
  some(value)

converter toPixelBuffer*(image: Image): PixelBuffer {.inline.} =
  ## Borrows the image's premultiplied pixels; keep the image alive while using
  ## the returned buffer. Nil or empty images yield an empty buffer.
  if not image.isNil and image.data.len > 0:
    result = PixelBuffer(
      data: image.data[0].addr,
      size: ivec2(image.width.int32, image.height.int32),
      format: rgbx_32bit,
    )

proc atlasUsage*(renderer: FigRenderer[SiwinRenderBackend]): AtlasUsage {.inline.} =
  nativeAtlasUsage(renderer.native)

func usedRatio*(usage: AtlasUsage): float32 {.inline.} =
  if usage.atlasArea <= 0:
    return 0.0'f32
  usage.usedArea.float32 / usage.atlasArea.float32

func packedRatio*(usage: AtlasUsage): float32 {.inline.} =
  if usage.atlasArea <= 0:
    return 0.0'f32
  usage.packedArea.float32 / usage.atlasArea.float32

proc atlasGeneration*(renderer: FigRenderer[SiwinRenderBackend]): uint64 {.inline.} =
  nativeAtlasGeneration(renderer.native)

proc ensureImage*(
    renderer: FigRenderer[SiwinRenderBackend], id: ImageId, image: Image
): bool {.discardable, inline.} =
  nativeEnsureImage(renderer.native, id, image)

proc rebuildImageAtlas*(
    renderer: FigRenderer[SiwinRenderBackend], minimumSize = 0
) {.inline.} =
  nativeRebuildImageAtlas(renderer.native, minimumSize)

proc processImageMessages*(renderer: FigRenderer[SiwinRenderBackend]) {.inline.} =
  nativeProcessImageMessages(renderer.native)

proc replayImageMessages*(renderer: FigRenderer[SiwinRenderBackend]) {.inline.} =
  nativeReplayImageMessages(renderer.native)

proc retainAtlasResources*(
    renderer: FigRenderer[SiwinRenderBackend],
    fontIds: openArray[FontId],
    imageIds: openArray[ImageId],
) {.inline.} =
  nativeRetainAtlasResources(renderer.native, fontIds, imageIds)

proc newFigRenderer*(
    atlasSize: int, backendState: SiwinRenderBackend, pixelScale = 1.0'f32
): FigRenderer[SiwinRenderBackend] =
  FigRenderer[SiwinRenderBackend](
    atlasSize: atlasSize, pixelScale: pixelScale, backendState: backendState
  )

proc newSiwinWindow*(
    size = ivec2(1280, 720),
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
    resizable = true,
    frameless = false,
    transparent = false,
): Window =
  ## Creates the producer's platform window without importing Siwin locally.
  figdraw_native_abi.newSiwinWindow(
    size, fullscreen, title, vsync, msaa, resizable, frameless, transparent
  )

proc newPopupWindow*(
    parent: Window, placement: PopupPlacement, transparent = true, grab = true
): Window =
  figdraw_native_abi.newSiwinPopupWindow(parent, placement, transparent, grab)

proc setupBackend*(renderer: FigRenderer[SiwinRenderBackend], window: Window) =
  let native = figdraw_native_abi.newFigRenderer(
    renderer.atlasSize, renderer.backendState, renderer.pixelScale
  )
  figdraw_native_abi.setupBackend(native, window)
  let autoScale = figdraw_native_abi.configureUiScale(window, "HDI")
  renderer.native = native
  renderer.window = window
  renderer.backendState = default(SiwinRenderBackend)
  renderer.autoScale = autoScale

proc newSiwinWindow*(
    renderer: FigRenderer[SiwinRenderBackend],
    size = ivec2(1280, 720),
    fullscreen = false,
    title = "FigDraw",
    vsync = true,
    msaa = 0'i32,
    resizable = true,
    frameless = false,
    transparent = false,
): Window =
  result = newSiwinWindow(
    size, fullscreen, title, vsync, msaa, resizable, frameless, transparent
  )
  renderer.setupBackend(result)

proc nativeWindowKey*(window: Window): pointer {.inline.} =
  cast[pointer](window)

proc `icon=`*(window: Window, image: Image) {.inline.} =
  ## Converts image icons while preserving Siwin's distinct clear-icon call.
  if image.isNil or image.data.len == 0:
    figdraw_native_abi.`icon=`(window, nil)
  else:
    figdraw_native_abi.`icon=`(window, image.toPixelBuffer())

template `vsync=`*(window: Window, value: bool) =
  figdraw_native_abi.`vsync=`(window, value, false)

template firstStep*(window: Window) =
  figdraw_native_abi.firstStep(window, true)

template configureUiScale*(window: Window): bool =
  figdraw_native_abi.configureUiScale(window, "HDI")

proc beginFrame*(renderer: FigRenderer[SiwinRenderBackend]) =
  renderer.window.refreshUiScale(renderer.autoScale)
  figdraw_native_abi.beginFrame(renderer.native)

proc renderFrame*(
    renderer: FigRenderer[SiwinRenderBackend],
    renders: var Renders,
    size: vmath.Vec2,
    clearMain = true,
    clearColor = whiteColor,
) =
  figdraw_native_abi.renderFrame(renderer.native, renders, size, clearMain, clearColor)

proc renderFrame*(
    renderer: FigRenderer[SiwinRenderBackend],
    renders: var RenderFragments,
    size: vmath.Vec2,
    clearMain = true,
    clearColor = whiteColor,
) =
  figdraw_native_abi.renderFrame(renderer.native, renders, size, clearMain, clearColor)

proc siwinWindowTitle*(suffix = "Siwin RenderList"): string =
  "figdraw: " & siwinBackendName() & " + " & suffix

proc siwinWindowTitle*(
    renderer: FigRenderer[SiwinRenderBackend],
    window: Window,
    suffix = "Siwin RenderList",
): string =
  discard window
  "figdraw: " & renderer.backendName() & " + " & suffix
