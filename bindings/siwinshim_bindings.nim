import figdraw/windowing/siwinshim
import figdraw/figrender as fgr
when defined(macosx) and UseMetalBackend:
  import figdraw/windowing/siwinmetal

type
  SiwinWindowRef* = ref object
    inner: Window

  SiwinRendererRef* = ref object
    inner: fgr.FigRenderer[SiwinRenderBackend]

when defined(macosx) and UseMetalBackend:
  type
    SiwinMetalLayerRef* = ref object
      inner: MetalLayerHandle

var
  siwinBackendNameStorage {.threadvar.}: string
  siwinWindowTitleStorage {.threadvar.}: string
  siwinDisplayNameStorage {.threadvar.}: string
  siwinRendererBackendNameStorage {.threadvar.}: string
  siwinRendererWindowTitleStorage {.threadvar.}: string

proc siwinBackendNameBinding(): string =
  try:
    siwinBackendNameStorage = siwinBackendName()
    siwinBackendNameStorage
  except Exception:
    ""

proc siwinWindowTitleBinding(suffix: string): string =
  try:
    siwinWindowTitleStorage = siwinWindowTitle(suffix = suffix)
    siwinWindowTitleStorage
  except Exception:
    ""

proc sharedSiwinGlobalsPtrBinding(): uint64 =
  try:
    cast[uint64](sharedSiwinGlobals())
  except Exception:
    0'u64

proc newSiwinRendererBinding(atlasSize: int, pixelScale: float32): SiwinRendererRef =
  try:
    SiwinRendererRef(
      inner: fgr.newFigRenderer(atlasSize, SiwinRenderBackend(), pixelScale)
    )
  except Exception:
    nil

proc siwinBackendNameForRendererBinding(renderer: SiwinRendererRef): string =
  if renderer.isNil or renderer.inner.isNil:
    return ""
  try:
    siwinRendererBackendNameStorage = siwinBackendName(renderer.inner)
    siwinRendererBackendNameStorage
  except Exception:
    ""

proc newSiwinWindowBinding(
    width, height: int32,
    fullscreen: bool,
    title: string,
    vsync: bool,
    msaa: int32,
    resizable: bool,
    frameless: bool,
    transparent: bool,
): SiwinWindowRef =
  try:
    SiwinWindowRef(
      inner: newSiwinWindow(
        size = ivec2(width, height),
        fullscreen = fullscreen,
        title = title,
        vsync = vsync,
        msaa = msaa,
        resizable = resizable,
        frameless = frameless,
        transparent = transparent,
      )
    )
  except Exception:
    nil

proc newSiwinWindowForRendererBinding(
    renderer: SiwinRendererRef,
    width, height: int32,
    fullscreen: bool,
    title: string,
    vsync: bool,
    msaa: int32,
    resizable: bool,
    frameless: bool,
    transparent: bool,
): SiwinWindowRef =
  if renderer.isNil or renderer.inner.isNil:
    return nil
  try:
    SiwinWindowRef(
      inner: newSiwinWindow(
        renderer = renderer.inner,
        size = ivec2(width, height),
        fullscreen = fullscreen,
        title = title,
        vsync = vsync,
        msaa = msaa,
        resizable = resizable,
        frameless = frameless,
        transparent = transparent,
      )
    )
  except Exception:
    nil

proc closeWindowBinding(window: SiwinWindowRef) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.close()
  except Exception:
    discard

proc stepWindowBinding(window: SiwinWindowRef) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.step()
  except Exception:
    discard

proc firstStepWindowBinding(window: SiwinWindowRef, makeVisible = true) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.firstStep(makeVisible)
  except Exception:
    discard

proc redrawWindowBinding(window: SiwinWindowRef) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.redraw()
  except Exception:
    discard

proc makeCurrentWindowBinding(window: SiwinWindowRef) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.makeCurrent()
  except Exception:
    discard

proc windowIsOpenBinding(window: SiwinWindowRef): bool =
  if window.isNil or window.inner.isNil:
    return false
  window.inner.opened()

proc siwinDisplayServerNameBinding(window: SiwinWindowRef): string =
  if window.isNil or window.inner.isNil:
    return ""
  try:
    siwinDisplayNameStorage = siwinDisplayServerName(window.inner)
    siwinDisplayNameStorage
  except Exception:
    ""

proc siwinWindowTitleForRendererBinding(
    renderer: SiwinRendererRef, window: SiwinWindowRef, suffix: string
): string =
  if renderer.isNil or renderer.inner.isNil or window.isNil or window.inner.isNil:
    return ""
  try:
    siwinRendererWindowTitleStorage =
      siwinWindowTitle(renderer.inner, window.inner, suffix = suffix)
    siwinRendererWindowTitleStorage
  except Exception:
    ""

proc backingWidthBinding(window: SiwinWindowRef): int32 =
  if window.isNil or window.inner.isNil:
    return 0'i32
  try:
    window.inner.backingSize().x
  except Exception:
    0'i32

proc backingHeightBinding(window: SiwinWindowRef): int32 =
  if window.isNil or window.inner.isNil:
    return 0'i32
  try:
    window.inner.backingSize().y
  except Exception:
    0'i32

proc logicalWidthBinding(window: SiwinWindowRef): float32 =
  if window.isNil or window.inner.isNil:
    return 0'f32
  try:
    window.inner.logicalSize().x
  except Exception:
    0'f32

proc logicalHeightBinding(window: SiwinWindowRef): float32 =
  if window.isNil or window.inner.isNil:
    return 0'f32
  try:
    window.inner.logicalSize().y
  except Exception:
    0'f32

proc contentScaleBinding(window: SiwinWindowRef): float32 =
  if window.isNil or window.inner.isNil:
    return 1'f32
  try:
    window.inner.contentScale()
  except Exception:
    1'f32

proc configureUiScaleBinding(window: SiwinWindowRef, envVar: string): bool =
  if window.isNil or window.inner.isNil:
    return false
  try:
    window.inner.configureUiScale(envVar = envVar)
  except Exception:
    false

proc refreshUiScaleBinding(window: SiwinWindowRef, autoScale: bool) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.refreshUiScale(autoScale)
  except Exception:
    discard

proc presentNowBinding(window: SiwinWindowRef) =
  if window.isNil or window.inner.isNil:
    return
  try:
    window.inner.presentNow()
  except Exception:
    discard

proc setupBackendBinding(renderer: SiwinRendererRef, window: SiwinWindowRef) =
  if renderer.isNil or renderer.inner.isNil or window.isNil or window.inner.isNil:
    return
  try:
    setupBackend(renderer.inner, window.inner)
  except Exception:
    discard

proc beginFrameBinding(renderer: SiwinRendererRef) =
  if renderer.isNil or renderer.inner.isNil:
    return
  try:
    beginFrame(renderer.inner)
  except Exception:
    discard

proc endFrameBinding(renderer: SiwinRendererRef) =
  if renderer.isNil or renderer.inner.isNil:
    return
  try:
    endFrame(renderer.inner)
  except Exception:
    discard

proc renderFrameBinding(
    renderer: SiwinRendererRef, renders: Renders, width, height: float32
) =
  if renderer.isNil or renderer.inner.isNil or renders.isNil:
    return
  try:
    renderer.inner.renderFrame(renders.inner, vec2(width, height))
  except Exception:
    discard

when defined(macosx) and UseMetalBackend:
  proc attachMetalLayerBinding(
      window: SiwinWindowRef, devicePtr: uint64
  ): SiwinMetalLayerRef =
    if window.isNil or window.inner.isNil or devicePtr == 0'u64:
      return nil
    try:
      SiwinMetalLayerRef(
        inner: attachMetalLayer(
          window.inner,
          cast[siwinmetal.MTLDevice](cast[pointer](devicePtr)),
        )
      )
    except Exception:
      nil

  proc updateMetalLayerBinding(layer: SiwinMetalLayerRef, window: SiwinWindowRef) =
    if layer.isNil or window.isNil or window.inner.isNil:
      return
    try:
      updateMetalLayer(layer.inner, window.inner)
    except Exception:
      discard

  proc setOpaqueBinding(layer: SiwinMetalLayerRef, opaque: bool) =
    if layer.isNil:
      return
    try:
      siwinshim.setOpaque(layer.inner, opaque)
    except Exception:
      discard

exportRefObject SiwinWindowRef:
  procs:
    closeWindowBinding(SiwinWindowRef)
    firstStepWindowBinding(SiwinWindowRef, bool)
    stepWindowBinding(SiwinWindowRef)
    redrawWindowBinding(SiwinWindowRef)
    makeCurrentWindowBinding(SiwinWindowRef)
    windowIsOpenBinding(SiwinWindowRef)
    siwinDisplayServerNameBinding(SiwinWindowRef)
    backingWidthBinding(SiwinWindowRef)
    backingHeightBinding(SiwinWindowRef)
    logicalWidthBinding(SiwinWindowRef)
    logicalHeightBinding(SiwinWindowRef)
    contentScaleBinding(SiwinWindowRef)
    configureUiScaleBinding(SiwinWindowRef, string)
    refreshUiScaleBinding(SiwinWindowRef, bool)
    presentNowBinding(SiwinWindowRef)

exportRefObject SiwinRendererRef:
  procs:
    siwinBackendNameForRendererBinding(SiwinRendererRef)
    setupBackendBinding(SiwinRendererRef, SiwinWindowRef)
    beginFrameBinding(SiwinRendererRef)
    endFrameBinding(SiwinRendererRef)
    renderFrameBinding(SiwinRendererRef, Renders, float32, float32)

when defined(macosx) and UseMetalBackend:
  exportRefObject SiwinMetalLayerRef:
    procs:
      updateMetalLayerBinding(SiwinMetalLayerRef, SiwinWindowRef)
      setOpaqueBinding(SiwinMetalLayerRef, bool)

exportProcs:
  siwinBackendNameBinding
  siwinWindowTitleBinding
  sharedSiwinGlobalsPtrBinding
  newSiwinRendererBinding
  newSiwinWindowBinding
  newSiwinWindowForRendererBinding

when defined(macosx) and UseMetalBackend:
  exportProcs:
    attachMetalLayerBinding
