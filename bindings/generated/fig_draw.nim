import bumpy, chroma, unicode, vmath

export bumpy, chroma, unicode, vmath

when defined(windows):
  const libName = "fig_draw.dll"
elif defined(macosx):
  const libName = "libfig_draw.dylib"
else:
  const libName = "libfig_draw.so"

{.push dynlib: libName.}

type FigDrawError = object of ValueError

type FigKind* = enum
  FigKind

type FigObj = object
  reference: pointer

type Fig* = ref FigObj

proc fig_draw_fig_unref(x: FigObj) {.importc: "fig_draw_fig_unref", cdecl.}

proc `=destroy`(x: var FigObj) =
  fig_draw_fig_unref(x)

type RenderListObj = object
  reference: pointer

type RenderList* = ref RenderListObj

proc fig_draw_render_list_unref(x: RenderListObj) {.importc: "fig_draw_render_list_unref", cdecl.}

proc `=destroy`(x: var RenderListObj) =
  fig_draw_render_list_unref(x)

type RendersObj = object
  reference: pointer

type Renders* = ref RendersObj

proc fig_draw_renders_unref(x: RendersObj) {.importc: "fig_draw_renders_unref", cdecl.}

proc `=destroy`(x: var RendersObj) =
  fig_draw_renders_unref(x)

type SiwinWindowRefObj = object
  reference: pointer

type SiwinWindowRef* = ref SiwinWindowRefObj

proc fig_draw_siwin_window_ref_unref(x: SiwinWindowRefObj) {.importc: "fig_draw_siwin_window_ref_unref", cdecl.}

proc `=destroy`(x: var SiwinWindowRefObj) =
  fig_draw_siwin_window_ref_unref(x)

type SiwinRendererRefObj = object
  reference: pointer

type SiwinRendererRef* = ref SiwinRendererRefObj

proc fig_draw_siwin_renderer_ref_unref(x: SiwinRendererRefObj) {.importc: "fig_draw_siwin_renderer_ref_unref", cdecl.}

proc `=destroy`(x: var SiwinRendererRefObj) =
  fig_draw_siwin_renderer_ref_unref(x)

type SiwinMetalLayerRefObj = object
  reference: pointer

type SiwinMetalLayerRef* = ref SiwinMetalLayerRefObj

proc fig_draw_siwin_metal_layer_ref_unref(x: SiwinMetalLayerRefObj) {.importc: "fig_draw_siwin_metal_layer_ref_unref", cdecl.}

proc `=destroy`(x: var SiwinMetalLayerRefObj) =
  fig_draw_siwin_metal_layer_ref_unref(x)

proc fig_draw_new_fig(): Fig {.importc: "fig_draw_new_fig", cdecl.}

proc newFig*(): Fig {.inline.} =
  result = fig_draw_new_fig()

proc fig_draw_fig_copy(fig: Fig): Fig {.importc: "fig_draw_fig_copy", cdecl.}

proc copy*(fig: Fig): Fig {.inline.} =
  result = fig_draw_fig_copy(fig)

proc fig_draw_fig_kind(fig: Fig): FigKind {.importc: "fig_draw_fig_kind", cdecl.}

proc kind*(fig: Fig): FigKind {.inline.} =
  result = fig_draw_fig_kind(fig)

proc fig_draw_fig_set_kind(fig: Fig, kind: FigKind) {.importc: "fig_draw_fig_set_kind", cdecl.}

proc setKind*(fig: Fig, kind: FigKind) {.inline.} =
  fig_draw_fig_set_kind(fig, kind)

proc fig_draw_fig_z_level(fig: Fig): ZLevel {.importc: "fig_draw_fig_z_level", cdecl.}

proc zLevel*(fig: Fig): ZLevel {.inline.} =
  result = fig_draw_fig_z_level(fig)

proc fig_draw_fig_set_zlevel(fig: Fig, z_level: ZLevel) {.importc: "fig_draw_fig_set_zlevel", cdecl.}

proc setZLevel*(fig: Fig, zLevel: ZLevel) {.inline.} =
  fig_draw_fig_set_zlevel(fig, zLevel)

proc fig_draw_fig_x(fig: Fig): float32 {.importc: "fig_draw_fig_x", cdecl.}

proc x*(fig: Fig): float32 {.inline.} =
  result = fig_draw_fig_x(fig)

proc fig_draw_fig_y(fig: Fig): float32 {.importc: "fig_draw_fig_y", cdecl.}

proc y*(fig: Fig): float32 {.inline.} =
  result = fig_draw_fig_y(fig)

proc fig_draw_fig_width(fig: Fig): float32 {.importc: "fig_draw_fig_width", cdecl.}

proc width*(fig: Fig): float32 {.inline.} =
  result = fig_draw_fig_width(fig)

proc fig_draw_fig_height(fig: Fig): float32 {.importc: "fig_draw_fig_height", cdecl.}

proc height*(fig: Fig): float32 {.inline.} =
  result = fig_draw_fig_height(fig)

proc fig_draw_fig_set_screen_box(fig: Fig, x: float32, y: float32, w: float32, h: float32) {.importc: "fig_draw_fig_set_screen_box", cdecl.}

proc setScreenBox*(fig: Fig, x: float32, y: float32, w: float32, h: float32) {.inline.} =
  fig_draw_fig_set_screen_box(fig, x, y, w, h)

proc fig_draw_fig_set_fill_color(fig: Fig, r: uint8, g: uint8, b: uint8, a: uint8) {.importc: "fig_draw_fig_set_fill_color", cdecl.}

proc setFillColor*(fig: Fig, r: uint8, g: uint8, b: uint8, a: uint8) {.inline.} =
  fig_draw_fig_set_fill_color(fig, r, g, b, a)

proc fig_draw_fig_set_rotation(fig: Fig, rotation: float32) {.importc: "fig_draw_fig_set_rotation", cdecl.}

proc setRotation*(fig: Fig, rotation: float32) {.inline.} =
  fig_draw_fig_set_rotation(fig, rotation)

proc fig_draw_new_render_list(): RenderList {.importc: "fig_draw_new_render_list", cdecl.}

proc newRenderList*(): RenderList {.inline.} =
  result = fig_draw_new_render_list()

proc fig_draw_render_list_copy(list: RenderList): RenderList {.importc: "fig_draw_render_list_copy", cdecl.}

proc copy*(list: RenderList): RenderList {.inline.} =
  result = fig_draw_render_list_copy(list)

proc fig_draw_render_list_clear(list: RenderList) {.importc: "fig_draw_render_list_clear", cdecl.}

proc clear*(list: RenderList) {.inline.} =
  fig_draw_render_list_clear(list)

proc fig_draw_render_list_node_count(list: RenderList): int {.importc: "fig_draw_render_list_node_count", cdecl.}

proc nodeCount*(list: RenderList): int {.inline.} =
  result = fig_draw_render_list_node_count(list)

proc fig_draw_render_list_root_count(list: RenderList): int {.importc: "fig_draw_render_list_root_count", cdecl.}

proc rootCount*(list: RenderList): int {.inline.} =
  result = fig_draw_render_list_root_count(list)

proc fig_draw_render_list_add_root(list: RenderList, root: Fig): int16 {.importc: "fig_draw_render_list_add_root", cdecl.}

proc addRoot*(list: RenderList, root: Fig): int16 {.inline.} =
  result = fig_draw_render_list_add_root(list, root)

proc fig_draw_render_list_add_child(list: RenderList, parent_idx: int16, child: Fig): int16 {.importc: "fig_draw_render_list_add_child", cdecl.}

proc addChild*(list: RenderList, parentIdx: int16, child: Fig): int16 {.inline.} =
  result = fig_draw_render_list_add_child(list, parentIdx, child)

proc fig_draw_render_list_get_node(list: RenderList, node_idx: int16): Fig {.importc: "fig_draw_render_list_get_node", cdecl.}

proc getNode*(list: RenderList, nodeIdx: int16): Fig {.inline.} =
  result = fig_draw_render_list_get_node(list, nodeIdx)

proc fig_draw_render_list_get_root_id(list: RenderList, root_idx: int16): int16 {.importc: "fig_draw_render_list_get_root_id", cdecl.}

proc getRootId*(list: RenderList, rootIdx: int16): int16 {.inline.} =
  result = fig_draw_render_list_get_root_id(list, rootIdx)

proc fig_draw_new_renders(): Renders {.importc: "fig_draw_new_renders", cdecl.}

proc newRenders*(): Renders {.inline.} =
  result = fig_draw_new_renders()

proc fig_draw_renders_clear(renders: Renders) {.importc: "fig_draw_renders_clear", cdecl.}

proc clear*(renders: Renders) {.inline.} =
  fig_draw_renders_clear(renders)

proc fig_draw_renders_contains_layer(renders: Renders, z_level: ZLevel): bool {.importc: "fig_draw_renders_contains_layer", cdecl.}

proc containsLayer*(renders: Renders, zLevel: ZLevel): bool {.inline.} =
  result = fig_draw_renders_contains_layer(renders, zLevel)

proc fig_draw_renders_add_root(renders: Renders, z_level: ZLevel, root: Fig): int16 {.importc: "fig_draw_renders_add_root", cdecl.}

proc addRoot*(renders: Renders, zLevel: ZLevel, root: Fig): int16 {.inline.} =
  result = fig_draw_renders_add_root(renders, zLevel, root)

proc fig_draw_renders_add_child(renders: Renders, z_level: ZLevel, parent_idx: int16, child: Fig): int16 {.importc: "fig_draw_renders_add_child", cdecl.}

proc addChild*(renders: Renders, zLevel: ZLevel, parentIdx: int16, child: Fig): int16 {.inline.} =
  result = fig_draw_renders_add_child(renders, zLevel, parentIdx, child)

proc fig_draw_renders_layer_node_count(renders: Renders, z_level: ZLevel): int {.importc: "fig_draw_renders_layer_node_count", cdecl.}

proc layerNodeCount*(renders: Renders, zLevel: ZLevel): int {.inline.} =
  result = fig_draw_renders_layer_node_count(renders, zLevel)

proc fig_draw_renders_layer_root_count(renders: Renders, z_level: ZLevel): int {.importc: "fig_draw_renders_layer_root_count", cdecl.}

proc layerRootCount*(renders: Renders, zLevel: ZLevel): int {.inline.} =
  result = fig_draw_renders_layer_root_count(renders, zLevel)

proc fig_draw_renders_get_layer_node(renders: Renders, z_level: ZLevel, node_idx: int16): Fig {.importc: "fig_draw_renders_get_layer_node", cdecl.}

proc getLayerNode*(renders: Renders, zLevel: ZLevel, nodeIdx: int16): Fig {.inline.} =
  result = fig_draw_renders_get_layer_node(renders, zLevel, nodeIdx)

proc fig_draw_new_rectangle_fig(x: float32, y: float32, w: float32, h: float32): Fig {.importc: "fig_draw_new_rectangle_fig", cdecl.}

proc newRectangleFig*(x: float32, y: float32, w: float32, h: float32): Fig {.inline.} =
  result = fig_draw_new_rectangle_fig(x, y, w, h)

proc fig_draw_new_text_fig(x: float32, y: float32, w: float32, h: float32): Fig {.importc: "fig_draw_new_text_fig", cdecl.}

proc newTextFig*(x: float32, y: float32, w: float32, h: float32): Fig {.inline.} =
  result = fig_draw_new_text_fig(x, y, w, h)

proc fig_draw_new_image_fig(x: float32, y: float32, w: float32, h: float32, image_id: int64): Fig {.importc: "fig_draw_new_image_fig", cdecl.}

proc newImageFig*(x: float32, y: float32, w: float32, h: float32, imageId: int64): Fig {.inline.} =
  result = fig_draw_new_image_fig(x, y, w, h, imageId)

proc fig_draw_new_transform_fig(x: float32, y: float32, w: float32, h: float32, tx: float32, ty: float32): Fig {.importc: "fig_draw_new_transform_fig", cdecl.}

proc newTransformFig*(x: float32, y: float32, w: float32, h: float32, tx: float32, ty: float32): Fig {.inline.} =
  result = fig_draw_new_transform_fig(x, y, w, h, tx, ty)

proc fig_draw_fig_data_dir(): cstring {.importc: "fig_draw_fig_data_dir", cdecl.}

proc figDataDir*(): cstring {.inline.} =
  result = fig_draw_fig_data_dir()

proc fig_draw_set_fig_data_dir(dir: cstring) {.importc: "fig_draw_set_fig_data_dir", cdecl.}

proc setFigDataDir*(dir: string) {.inline.} =
  fig_draw_set_fig_data_dir(dir.cstring)

proc fig_draw_fig_ui_scale(): float32 {.importc: "fig_draw_fig_ui_scale", cdecl.}

proc figUiScale*(): float32 {.inline.} =
  result = fig_draw_fig_ui_scale()

proc fig_draw_set_fig_ui_scale(scale: float32) {.importc: "fig_draw_set_fig_ui_scale", cdecl.}

proc setFigUiScale*(scale: float32) {.inline.} =
  fig_draw_set_fig_ui_scale(scale)

proc fig_draw_scaled(a: float32): float32 {.importc: "fig_draw_scaled", cdecl.}

proc scaled*(a: float32): float32 {.inline.} =
  result = fig_draw_scaled(a)

proc fig_draw_descaled(a: float32): float32 {.importc: "fig_draw_descaled", cdecl.}

proc descaled*(a: float32): float32 {.inline.} =
  result = fig_draw_descaled(a)

proc fig_draw_siwin_window_ref_close_window_binding(window: SiwinWindowRef) {.importc: "fig_draw_siwin_window_ref_close_window_binding", cdecl.}

proc closeWindowBinding*(window: SiwinWindowRef) {.inline.} =
  fig_draw_siwin_window_ref_close_window_binding(window)

proc fig_draw_siwin_window_ref_step_window_binding(window: SiwinWindowRef) {.importc: "fig_draw_siwin_window_ref_step_window_binding", cdecl.}

proc stepWindowBinding*(window: SiwinWindowRef) {.inline.} =
  fig_draw_siwin_window_ref_step_window_binding(window)

proc fig_draw_siwin_window_ref_make_current_window_binding(window: SiwinWindowRef) {.importc: "fig_draw_siwin_window_ref_make_current_window_binding", cdecl.}

proc makeCurrentWindowBinding*(window: SiwinWindowRef) {.inline.} =
  fig_draw_siwin_window_ref_make_current_window_binding(window)

proc fig_draw_siwin_window_ref_window_is_open_binding(window: SiwinWindowRef): bool {.importc: "fig_draw_siwin_window_ref_window_is_open_binding", cdecl.}

proc windowIsOpenBinding*(window: SiwinWindowRef): bool {.inline.} =
  result = fig_draw_siwin_window_ref_window_is_open_binding(window)

proc fig_draw_siwin_window_ref_siwin_display_server_name_binding(window: SiwinWindowRef): cstring {.importc: "fig_draw_siwin_window_ref_siwin_display_server_name_binding", cdecl.}

proc siwinDisplayServerNameBinding*(window: SiwinWindowRef): cstring {.inline.} =
  result = fig_draw_siwin_window_ref_siwin_display_server_name_binding(window)

proc fig_draw_siwin_window_ref_backing_width_binding(window: SiwinWindowRef): int32 {.importc: "fig_draw_siwin_window_ref_backing_width_binding", cdecl.}

proc backingWidthBinding*(window: SiwinWindowRef): int32 {.inline.} =
  result = fig_draw_siwin_window_ref_backing_width_binding(window)

proc fig_draw_siwin_window_ref_backing_height_binding(window: SiwinWindowRef): int32 {.importc: "fig_draw_siwin_window_ref_backing_height_binding", cdecl.}

proc backingHeightBinding*(window: SiwinWindowRef): int32 {.inline.} =
  result = fig_draw_siwin_window_ref_backing_height_binding(window)

proc fig_draw_siwin_window_ref_logical_width_binding(window: SiwinWindowRef): float32 {.importc: "fig_draw_siwin_window_ref_logical_width_binding", cdecl.}

proc logicalWidthBinding*(window: SiwinWindowRef): float32 {.inline.} =
  result = fig_draw_siwin_window_ref_logical_width_binding(window)

proc fig_draw_siwin_window_ref_logical_height_binding(window: SiwinWindowRef): float32 {.importc: "fig_draw_siwin_window_ref_logical_height_binding", cdecl.}

proc logicalHeightBinding*(window: SiwinWindowRef): float32 {.inline.} =
  result = fig_draw_siwin_window_ref_logical_height_binding(window)

proc fig_draw_siwin_window_ref_content_scale_binding(window: SiwinWindowRef): float32 {.importc: "fig_draw_siwin_window_ref_content_scale_binding", cdecl.}

proc contentScaleBinding*(window: SiwinWindowRef): float32 {.inline.} =
  result = fig_draw_siwin_window_ref_content_scale_binding(window)

proc fig_draw_siwin_window_ref_configure_ui_scale_binding(window: SiwinWindowRef, env_var: cstring): bool {.importc: "fig_draw_siwin_window_ref_configure_ui_scale_binding", cdecl.}

proc configureUiScaleBinding*(window: SiwinWindowRef, envVar: string): bool {.inline.} =
  result = fig_draw_siwin_window_ref_configure_ui_scale_binding(window, envVar.cstring)

proc fig_draw_siwin_window_ref_refresh_ui_scale_binding(window: SiwinWindowRef, auto_scale: bool) {.importc: "fig_draw_siwin_window_ref_refresh_ui_scale_binding", cdecl.}

proc refreshUiScaleBinding*(window: SiwinWindowRef, autoScale: bool) {.inline.} =
  fig_draw_siwin_window_ref_refresh_ui_scale_binding(window, autoScale)

proc fig_draw_siwin_window_ref_present_now_binding(window: SiwinWindowRef) {.importc: "fig_draw_siwin_window_ref_present_now_binding", cdecl.}

proc presentNowBinding*(window: SiwinWindowRef) {.inline.} =
  fig_draw_siwin_window_ref_present_now_binding(window)

proc fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(renderer: SiwinRendererRef): cstring {.importc: "fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding", cdecl.}

proc siwinBackendNameForRendererBinding*(renderer: SiwinRendererRef): cstring {.inline.} =
  result = fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(renderer)

proc fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(renderer: SiwinRendererRef, window: SiwinWindowRef, suffix: cstring): cstring {.importc: "fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding", cdecl.}

proc siwinWindowTitleForRendererBinding*(renderer: SiwinRendererRef, window: SiwinWindowRef, suffix: string): cstring {.inline.} =
  result = fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(renderer, window, suffix.cstring)

proc fig_draw_siwin_renderer_ref_setup_backend_binding(renderer: SiwinRendererRef, window: SiwinWindowRef) {.importc: "fig_draw_siwin_renderer_ref_setup_backend_binding", cdecl.}

proc setupBackendBinding*(renderer: SiwinRendererRef, window: SiwinWindowRef) {.inline.} =
  fig_draw_siwin_renderer_ref_setup_backend_binding(renderer, window)

proc fig_draw_siwin_renderer_ref_begin_frame_binding(renderer: SiwinRendererRef) {.importc: "fig_draw_siwin_renderer_ref_begin_frame_binding", cdecl.}

proc beginFrameBinding*(renderer: SiwinRendererRef) {.inline.} =
  fig_draw_siwin_renderer_ref_begin_frame_binding(renderer)

proc fig_draw_siwin_renderer_ref_end_frame_binding(renderer: SiwinRendererRef) {.importc: "fig_draw_siwin_renderer_ref_end_frame_binding", cdecl.}

proc endFrameBinding*(renderer: SiwinRendererRef) {.inline.} =
  fig_draw_siwin_renderer_ref_end_frame_binding(renderer)

proc fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(layer: SiwinMetalLayerRef, window: SiwinWindowRef) {.importc: "fig_draw_siwin_metal_layer_ref_update_metal_layer_binding", cdecl.}

proc updateMetalLayerBinding*(layer: SiwinMetalLayerRef, window: SiwinWindowRef) {.inline.} =
  fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(layer, window)

proc fig_draw_siwin_metal_layer_ref_set_opaque_binding(layer: SiwinMetalLayerRef, opaque: bool) {.importc: "fig_draw_siwin_metal_layer_ref_set_opaque_binding", cdecl.}

proc setOpaqueBinding*(layer: SiwinMetalLayerRef, opaque: bool) {.inline.} =
  fig_draw_siwin_metal_layer_ref_set_opaque_binding(layer, opaque)

proc fig_draw_siwin_backend_name_binding(): cstring {.importc: "fig_draw_siwin_backend_name_binding", cdecl.}

proc siwinBackendNameBinding*(): cstring {.inline.} =
  result = fig_draw_siwin_backend_name_binding()

proc fig_draw_siwin_window_title_binding(suffix: cstring): cstring {.importc: "fig_draw_siwin_window_title_binding", cdecl.}

proc siwinWindowTitleBinding*(suffix: string): cstring {.inline.} =
  result = fig_draw_siwin_window_title_binding(suffix.cstring)

proc fig_draw_shared_siwin_globals_ptr_binding(): uint64 {.importc: "fig_draw_shared_siwin_globals_ptr_binding", cdecl.}

proc sharedSiwinGlobalsPtrBinding*(): uint64 {.inline.} =
  result = fig_draw_shared_siwin_globals_ptr_binding()

proc fig_draw_new_siwin_renderer_binding(atlas_size: int, pixel_scale: float32): SiwinRendererRef {.importc: "fig_draw_new_siwin_renderer_binding", cdecl.}

proc newSiwinRendererBinding*(atlasSize: int, pixelScale: float32): SiwinRendererRef {.inline.} =
  result = fig_draw_new_siwin_renderer_binding(atlasSize, pixelScale)

proc fig_draw_new_siwin_window_binding(width: int32, height: int32, fullscreen: bool, title: cstring, vsync: bool, msaa: int32, resizable: bool, frameless: bool, transparent: bool): SiwinWindowRef {.importc: "fig_draw_new_siwin_window_binding", cdecl.}

proc newSiwinWindowBinding*(width: int32, height: int32, fullscreen: bool, title: string, vsync: bool, msaa: int32, resizable: bool, frameless: bool, transparent: bool): SiwinWindowRef {.inline.} =
  result = fig_draw_new_siwin_window_binding(width, height, fullscreen, title.cstring, vsync, msaa, resizable, frameless, transparent)

proc fig_draw_new_siwin_window_for_renderer_binding(renderer: SiwinRendererRef, width: int32, height: int32, fullscreen: bool, title: cstring, vsync: bool, msaa: int32, resizable: bool, frameless: bool, transparent: bool): SiwinWindowRef {.importc: "fig_draw_new_siwin_window_for_renderer_binding", cdecl.}

proc newSiwinWindowForRendererBinding*(renderer: SiwinRendererRef, width: int32, height: int32, fullscreen: bool, title: string, vsync: bool, msaa: int32, resizable: bool, frameless: bool, transparent: bool): SiwinWindowRef {.inline.} =
  result = fig_draw_new_siwin_window_for_renderer_binding(renderer, width, height, fullscreen, title.cstring, vsync, msaa, resizable, frameless, transparent)

proc fig_draw_attach_metal_layer_binding(window: SiwinWindowRef, device_ptr: uint64): SiwinMetalLayerRef {.importc: "fig_draw_attach_metal_layer_binding", cdecl.}

proc attachMetalLayerBinding*(window: SiwinWindowRef, devicePtr: uint64): SiwinMetalLayerRef {.inline.} =
  result = fig_draw_attach_metal_layer_binding(window, devicePtr)

