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

proc fig_draw_siwin_backend_name_binding(): cstring {.importc: "fig_draw_siwin_backend_name_binding", cdecl.}

proc siwinBackendNameBinding*(): cstring {.inline.} =
  result = fig_draw_siwin_backend_name_binding()

proc fig_draw_siwin_window_title_binding(suffix: cstring): cstring {.importc: "fig_draw_siwin_window_title_binding", cdecl.}

proc siwinWindowTitleBinding*(suffix: string): cstring {.inline.} =
  result = fig_draw_siwin_window_title_binding(suffix.cstring)

