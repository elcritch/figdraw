when not defined(gcArc) and not defined(gcOrc):
  {.error: "Please use --gc:arc or --gc:orc when using Genny.".}

when (NimMajor, NimMinor, NimPatch) == (1, 6, 2):
  {.error: "Nim 1.6.2 not supported with Genny due to FFI issues.".}
proc fig_draw_fig_unref*(x: Fig) {.raises: [], cdecl, exportc, dynlib.} =
  GC_unref(x)

proc fig_draw_new_fig*(): Fig {.raises: [], cdecl, exportc, dynlib.} =
  newFig()

proc fig_draw_fig_copy*(fig: Fig): Fig {.raises: [], cdecl, exportc, dynlib.} =
  copy(fig)

proc fig_draw_fig_kind*(fig: Fig): FigKind {.raises: [], cdecl, exportc, dynlib.} =
  kind(fig)

proc fig_draw_fig_set_kind*(fig: Fig, kind: FigKind) {.raises: [], cdecl, exportc, dynlib.} =
  setKind(fig, kind)

proc fig_draw_fig_z_level*(fig: Fig): ZLevel {.raises: [], cdecl, exportc, dynlib.} =
  zLevel(fig)

proc fig_draw_fig_set_zlevel*(fig: Fig, z_level: ZLevel) {.raises: [], cdecl, exportc, dynlib.} =
  setZLevel(fig, z_level)

proc fig_draw_fig_x*(fig: Fig): float32 {.raises: [], cdecl, exportc, dynlib.} =
  x(fig)

proc fig_draw_fig_y*(fig: Fig): float32 {.raises: [], cdecl, exportc, dynlib.} =
  y(fig)

proc fig_draw_fig_width*(fig: Fig): float32 {.raises: [], cdecl, exportc, dynlib.} =
  width(fig)

proc fig_draw_fig_height*(fig: Fig): float32 {.raises: [], cdecl, exportc, dynlib.} =
  height(fig)

proc fig_draw_fig_set_screen_box*(fig: Fig, x: float32, y: float32, w: float32, h: float32) {.raises: [], cdecl, exportc, dynlib.} =
  setScreenBox(fig, x, y, w, h)

proc fig_draw_fig_set_fill_color*(fig: Fig, r: uint8, g: uint8, b: uint8, a: uint8) {.raises: [], cdecl, exportc, dynlib.} =
  setFillColor(fig, r, g, b, a)

proc fig_draw_fig_set_rotation*(fig: Fig, rotation: float32) {.raises: [], cdecl, exportc, dynlib.} =
  setRotation(fig, rotation)

proc fig_draw_render_list_unref*(x: RenderList) {.raises: [], cdecl, exportc, dynlib.} =
  GC_unref(x)

proc fig_draw_new_render_list*(): RenderList {.raises: [], cdecl, exportc, dynlib.} =
  newRenderList()

proc fig_draw_render_list_copy*(list: RenderList): RenderList {.raises: [], cdecl, exportc, dynlib.} =
  copy(list)

proc fig_draw_render_list_clear*(list: RenderList) {.raises: [], cdecl, exportc, dynlib.} =
  clear(list)

proc fig_draw_render_list_node_count*(list: RenderList): int {.raises: [], cdecl, exportc, dynlib.} =
  nodeCount(list)

proc fig_draw_render_list_root_count*(list: RenderList): int {.raises: [], cdecl, exportc, dynlib.} =
  rootCount(list)

proc fig_draw_render_list_add_root*(list: RenderList, root: Fig): int16 {.raises: [], cdecl, exportc, dynlib.} =
  addRoot(list, root)

proc fig_draw_render_list_add_child*(list: RenderList, parent_idx: int16, child: Fig): int16 {.raises: [], cdecl, exportc, dynlib.} =
  addChild(list, parent_idx, child)

proc fig_draw_render_list_get_node*(list: RenderList, node_idx: int16): Fig {.raises: [], cdecl, exportc, dynlib.} =
  getNode(list, node_idx)

proc fig_draw_render_list_get_root_id*(list: RenderList, root_idx: int16): int16 {.raises: [], cdecl, exportc, dynlib.} =
  getRootId(list, root_idx)

proc fig_draw_renders_unref*(x: Renders) {.raises: [], cdecl, exportc, dynlib.} =
  GC_unref(x)

proc fig_draw_new_renders*(): Renders {.raises: [], cdecl, exportc, dynlib.} =
  newRenders()

proc fig_draw_renders_clear*(renders: Renders) {.raises: [], cdecl, exportc, dynlib.} =
  clear(renders)

proc fig_draw_renders_contains_layer*(renders: Renders, z_level: ZLevel): bool {.raises: [], cdecl, exportc, dynlib.} =
  containsLayer(renders, z_level)

proc fig_draw_renders_add_root*(renders: Renders, z_level: ZLevel, root: Fig): int16 {.raises: [], cdecl, exportc, dynlib.} =
  addRoot(renders, z_level, root)

proc fig_draw_renders_add_child*(renders: Renders, z_level: ZLevel, parent_idx: int16, child: Fig): int16 {.raises: [], cdecl, exportc, dynlib.} =
  addChild(renders, z_level, parent_idx, child)

proc fig_draw_renders_layer_node_count*(renders: Renders, z_level: ZLevel): int {.raises: [], cdecl, exportc, dynlib.} =
  layerNodeCount(renders, z_level)

proc fig_draw_renders_layer_root_count*(renders: Renders, z_level: ZLevel): int {.raises: [], cdecl, exportc, dynlib.} =
  layerRootCount(renders, z_level)

proc fig_draw_renders_get_layer_node*(renders: Renders, z_level: ZLevel, node_idx: int16): Fig {.raises: [], cdecl, exportc, dynlib.} =
  getLayerNode(renders, z_level, node_idx)

proc fig_draw_new_rectangle_fig*(x: float32, y: float32, w: float32, h: float32): Fig {.raises: [], cdecl, exportc, dynlib.} =
  newRectangleFig(x, y, w, h)

proc fig_draw_new_text_fig*(x: float32, y: float32, w: float32, h: float32): Fig {.raises: [], cdecl, exportc, dynlib.} =
  newTextFig(x, y, w, h)

proc fig_draw_new_image_fig*(x: float32, y: float32, w: float32, h: float32, image_id: int64): Fig {.raises: [], cdecl, exportc, dynlib.} =
  newImageFig(x, y, w, h, image_id)

proc fig_draw_new_transform_fig*(x: float32, y: float32, w: float32, h: float32, tx: float32, ty: float32): Fig {.raises: [], cdecl, exportc, dynlib.} =
  newTransformFig(x, y, w, h, tx, ty)

proc fig_draw_fig_data_dir*(): cstring {.raises: [], cdecl, exportc, dynlib.} =
  figDataDir().cstring

proc fig_draw_set_fig_data_dir*(dir: cstring) {.raises: [], cdecl, exportc, dynlib.} =
  setFigDataDir(dir.`$`)

proc fig_draw_fig_ui_scale*(): float32 {.raises: [], cdecl, exportc, dynlib.} =
  figUiScale()

proc fig_draw_set_fig_ui_scale*(scale: float32) {.raises: [], cdecl, exportc, dynlib.} =
  setFigUiScale(scale)

proc fig_draw_scaled*(a: float32): float32 {.raises: [], cdecl, exportc, dynlib.} =
  scaled(a)

proc fig_draw_descaled*(a: float32): float32 {.raises: [], cdecl, exportc, dynlib.} =
  descaled(a)

proc fig_draw_siwin_window_ref_unref*(x: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  GC_unref(x)

proc fig_draw_siwin_window_ref_close_window_binding*(window: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  closeWindowBinding(window)

proc fig_draw_siwin_window_ref_step_window_binding*(window: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  stepWindowBinding(window)

proc fig_draw_siwin_window_ref_make_current_window_binding*(window: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  makeCurrentWindowBinding(window)

proc fig_draw_siwin_window_ref_window_is_open_binding*(window: SiwinWindowRef): bool {.raises: [], cdecl, exportc, dynlib.} =
  windowIsOpenBinding(window)

proc fig_draw_siwin_window_ref_siwin_display_server_name_binding*(window: SiwinWindowRef): cstring {.raises: [], cdecl, exportc, dynlib.} =
  siwinDisplayServerNameBinding(window).cstring

proc fig_draw_siwin_window_ref_backing_width_binding*(window: SiwinWindowRef): int32 {.raises: [], cdecl, exportc, dynlib.} =
  backingWidthBinding(window)

proc fig_draw_siwin_window_ref_backing_height_binding*(window: SiwinWindowRef): int32 {.raises: [], cdecl, exportc, dynlib.} =
  backingHeightBinding(window)

proc fig_draw_siwin_window_ref_logical_width_binding*(window: SiwinWindowRef): float32 {.raises: [], cdecl, exportc, dynlib.} =
  logicalWidthBinding(window)

proc fig_draw_siwin_window_ref_logical_height_binding*(window: SiwinWindowRef): float32 {.raises: [], cdecl, exportc, dynlib.} =
  logicalHeightBinding(window)

proc fig_draw_siwin_window_ref_content_scale_binding*(window: SiwinWindowRef): float32 {.raises: [], cdecl, exportc, dynlib.} =
  contentScaleBinding(window)

proc fig_draw_siwin_window_ref_configure_ui_scale_binding*(window: SiwinWindowRef, env_var: cstring): bool {.raises: [], cdecl, exportc, dynlib.} =
  configureUiScaleBinding(window, env_var.`$`)

proc fig_draw_siwin_window_ref_refresh_ui_scale_binding*(window: SiwinWindowRef, auto_scale: bool) {.raises: [], cdecl, exportc, dynlib.} =
  refreshUiScaleBinding(window, auto_scale)

proc fig_draw_siwin_window_ref_present_now_binding*(window: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  presentNowBinding(window)

proc fig_draw_siwin_renderer_ref_unref*(x: SiwinRendererRef) {.raises: [], cdecl, exportc, dynlib.} =
  GC_unref(x)

proc fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding*(renderer: SiwinRendererRef): cstring {.raises: [], cdecl, exportc, dynlib.} =
  siwinBackendNameForRendererBinding(renderer).cstring

proc fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding*(renderer: SiwinRendererRef, window: SiwinWindowRef, suffix: cstring): cstring {.raises: [], cdecl, exportc, dynlib.} =
  siwinWindowTitleForRendererBinding(renderer, window, suffix.`$`).cstring

proc fig_draw_siwin_renderer_ref_setup_backend_binding*(renderer: SiwinRendererRef, window: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  setupBackendBinding(renderer, window)

proc fig_draw_siwin_renderer_ref_begin_frame_binding*(renderer: SiwinRendererRef) {.raises: [], cdecl, exportc, dynlib.} =
  beginFrameBinding(renderer)

proc fig_draw_siwin_renderer_ref_end_frame_binding*(renderer: SiwinRendererRef) {.raises: [], cdecl, exportc, dynlib.} =
  endFrameBinding(renderer)

proc fig_draw_siwin_metal_layer_ref_unref*(x: SiwinMetalLayerRef) {.raises: [], cdecl, exportc, dynlib.} =
  GC_unref(x)

proc fig_draw_siwin_metal_layer_ref_update_metal_layer_binding*(layer: SiwinMetalLayerRef, window: SiwinWindowRef) {.raises: [], cdecl, exportc, dynlib.} =
  updateMetalLayerBinding(layer, window)

proc fig_draw_siwin_metal_layer_ref_set_opaque_binding*(layer: SiwinMetalLayerRef, opaque: bool) {.raises: [], cdecl, exportc, dynlib.} =
  setOpaqueBinding(layer, opaque)

proc fig_draw_siwin_backend_name_binding*(): cstring {.raises: [], cdecl, exportc, dynlib.} =
  siwinBackendNameBinding().cstring

proc fig_draw_siwin_window_title_binding*(suffix: cstring): cstring {.raises: [], cdecl, exportc, dynlib.} =
  siwinWindowTitleBinding(suffix.`$`).cstring

proc fig_draw_shared_siwin_globals_ptr_binding*(): uint64 {.raises: [], cdecl, exportc, dynlib.} =
  sharedSiwinGlobalsPtrBinding()

proc fig_draw_new_siwin_renderer_binding*(atlas_size: int, pixel_scale: float32): SiwinRendererRef {.raises: [], cdecl, exportc, dynlib.} =
  newSiwinRendererBinding(atlas_size, pixel_scale)

proc fig_draw_new_siwin_window_binding*(width: int32, height: int32, fullscreen: bool, title: cstring, vsync: bool, msaa: int32, resizable: bool, frameless: bool, transparent: bool): SiwinWindowRef {.raises: [], cdecl, exportc, dynlib.} =
  newSiwinWindowBinding(width, height, fullscreen, title.`$`, vsync, msaa, resizable, frameless, transparent)

proc fig_draw_new_siwin_window_for_renderer_binding*(renderer: SiwinRendererRef, width: int32, height: int32, fullscreen: bool, title: cstring, vsync: bool, msaa: int32, resizable: bool, frameless: bool, transparent: bool): SiwinWindowRef {.raises: [], cdecl, exportc, dynlib.} =
  newSiwinWindowForRendererBinding(renderer, width, height, fullscreen, title.`$`, vsync, msaa, resizable, frameless, transparent)

proc fig_draw_attach_metal_layer_binding*(window: SiwinWindowRef, device_ptr: uint64): SiwinMetalLayerRef {.raises: [], cdecl, exportc, dynlib.} =
  attachMetalLayerBinding(window, device_ptr)

