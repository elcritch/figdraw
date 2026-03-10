#ifndef INCLUDE_FIGDRAW_H
#define INCLUDE_FIGDRAW_H

#include <stdint.h>

typedef char FigKind;
#define FIG_KIND 0

struct Fig;

struct RenderList;

struct Renders;

struct SiwinWindowRef;

struct SiwinRendererRef;

struct SiwinMetalLayerRef;

struct Fig {

  private:

  uint64_t reference;

  public:

  Fig();

  void free();

  Fig copy();

  FigKind kind();

  void setKind(FigKind kind);

  ZLevel zLevel();

  void setZLevel(ZLevel zLevel);

  float x();

  float y();

  float width();

  float height();

  void setScreenBox(float x, float y, float w, float h);

  void setFillColor(uint8_t r, uint8_t g, uint8_t b, uint8_t a);

  void setRotation(float rotation);

};

struct RenderList {

  private:

  uint64_t reference;

  public:

  RenderList();

  void free();

  RenderList copy();

  void clear();

  int64_t nodeCount();

  int64_t rootCount();

  int16_t addRoot(Fig root);

  int16_t addChild(int16_t parentIdx, Fig child);

  Fig getNode(int16_t nodeIdx);

  int16_t getRootId(int16_t rootIdx);

};

struct Renders {

  private:

  uint64_t reference;

  public:

  Renders();

  void free();

  void clear();

  bool containsLayer(ZLevel zLevel);

  int16_t addRoot(ZLevel zLevel, Fig root);

  int16_t addChild(ZLevel zLevel, int16_t parentIdx, Fig child);

  int64_t layerNodeCount(ZLevel zLevel);

  int64_t layerRootCount(ZLevel zLevel);

  Fig getLayerNode(ZLevel zLevel, int16_t nodeIdx);

};

struct SiwinWindowRef {

  private:

  uint64_t reference;

  public:

  void free();

  void closeWindowBinding();

  void stepWindowBinding();

  void makeCurrentWindowBinding();

  bool windowIsOpenBinding();

  const char* siwinDisplayServerNameBinding();

  int32_t backingWidthBinding();

  int32_t backingHeightBinding();

  float logicalWidthBinding();

  float logicalHeightBinding();

  float contentScaleBinding();

  bool configureUiScaleBinding(const char* envVar);

  void refreshUiScaleBinding(bool autoScale);

  void presentNowBinding();

};

struct SiwinRendererRef {

  private:

  uint64_t reference;

  public:

  void free();

  const char* siwinBackendNameForRendererBinding();

  const char* siwinWindowTitleForRendererBinding(SiwinWindowRef window, const char* suffix);

  void setupBackendBinding(SiwinWindowRef window);

  void beginFrameBinding();

  void endFrameBinding();

};

struct SiwinMetalLayerRef {

  private:

  uint64_t reference;

  public:

  void free();

  void updateMetalLayerBinding(SiwinWindowRef window);

  void setOpaqueBinding(bool opaque);

};

extern "C" {

void fig_draw_fig_unref(Fig fig);

Fig fig_draw_new_fig();

Fig fig_draw_fig_copy(Fig fig);

FigKind fig_draw_fig_kind(Fig fig);

void fig_draw_fig_set_kind(Fig fig, FigKind kind);

ZLevel fig_draw_fig_z_level(Fig fig);

void fig_draw_fig_set_zlevel(Fig fig, ZLevel z_level);

float fig_draw_fig_x(Fig fig);

float fig_draw_fig_y(Fig fig);

float fig_draw_fig_width(Fig fig);

float fig_draw_fig_height(Fig fig);

void fig_draw_fig_set_screen_box(Fig fig, float x, float y, float w, float h);

void fig_draw_fig_set_fill_color(Fig fig, uint8_t r, uint8_t g, uint8_t b, uint8_t a);

void fig_draw_fig_set_rotation(Fig fig, float rotation);

void fig_draw_render_list_unref(RenderList render_list);

RenderList fig_draw_new_render_list();

RenderList fig_draw_render_list_copy(RenderList list);

void fig_draw_render_list_clear(RenderList list);

int64_t fig_draw_render_list_node_count(RenderList list);

int64_t fig_draw_render_list_root_count(RenderList list);

int16_t fig_draw_render_list_add_root(RenderList list, Fig root);

int16_t fig_draw_render_list_add_child(RenderList list, int16_t parent_idx, Fig child);

Fig fig_draw_render_list_get_node(RenderList list, int16_t node_idx);

int16_t fig_draw_render_list_get_root_id(RenderList list, int16_t root_idx);

void fig_draw_renders_unref(Renders renders);

Renders fig_draw_new_renders();

void fig_draw_renders_clear(Renders renders);

bool fig_draw_renders_contains_layer(Renders renders, ZLevel z_level);

int16_t fig_draw_renders_add_root(Renders renders, ZLevel z_level, Fig root);

int16_t fig_draw_renders_add_child(Renders renders, ZLevel z_level, int16_t parent_idx, Fig child);

int64_t fig_draw_renders_layer_node_count(Renders renders, ZLevel z_level);

int64_t fig_draw_renders_layer_root_count(Renders renders, ZLevel z_level);

Fig fig_draw_renders_get_layer_node(Renders renders, ZLevel z_level, int16_t node_idx);

Fig fig_draw_new_rectangle_fig(float x, float y, float w, float h);

Fig fig_draw_new_text_fig(float x, float y, float w, float h);

Fig fig_draw_new_image_fig(float x, float y, float w, float h, int64_t image_id);

Fig fig_draw_new_transform_fig(float x, float y, float w, float h, float tx, float ty);

const char* fig_draw_fig_data_dir();

void fig_draw_set_fig_data_dir(const char* dir);

float fig_draw_fig_ui_scale();

void fig_draw_set_fig_ui_scale(float scale);

float fig_draw_scaled(float a);

float fig_draw_descaled(float a);

void fig_draw_siwin_window_ref_unref(SiwinWindowRef siwin_window_ref);

void fig_draw_siwin_window_ref_close_window_binding(SiwinWindowRef window);

void fig_draw_siwin_window_ref_step_window_binding(SiwinWindowRef window);

void fig_draw_siwin_window_ref_make_current_window_binding(SiwinWindowRef window);

bool fig_draw_siwin_window_ref_window_is_open_binding(SiwinWindowRef window);

const char* fig_draw_siwin_window_ref_siwin_display_server_name_binding(SiwinWindowRef window);

int32_t fig_draw_siwin_window_ref_backing_width_binding(SiwinWindowRef window);

int32_t fig_draw_siwin_window_ref_backing_height_binding(SiwinWindowRef window);

float fig_draw_siwin_window_ref_logical_width_binding(SiwinWindowRef window);

float fig_draw_siwin_window_ref_logical_height_binding(SiwinWindowRef window);

float fig_draw_siwin_window_ref_content_scale_binding(SiwinWindowRef window);

bool fig_draw_siwin_window_ref_configure_ui_scale_binding(SiwinWindowRef window, const char* env_var);

void fig_draw_siwin_window_ref_refresh_ui_scale_binding(SiwinWindowRef window, bool auto_scale);

void fig_draw_siwin_window_ref_present_now_binding(SiwinWindowRef window);

void fig_draw_siwin_renderer_ref_unref(SiwinRendererRef siwin_renderer_ref);

const char* fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(SiwinRendererRef renderer);

const char* fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(SiwinRendererRef renderer, SiwinWindowRef window, const char* suffix);

void fig_draw_siwin_renderer_ref_setup_backend_binding(SiwinRendererRef renderer, SiwinWindowRef window);

void fig_draw_siwin_renderer_ref_begin_frame_binding(SiwinRendererRef renderer);

void fig_draw_siwin_renderer_ref_end_frame_binding(SiwinRendererRef renderer);

void fig_draw_siwin_metal_layer_ref_unref(SiwinMetalLayerRef siwin_metal_layer_ref);

void fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(SiwinMetalLayerRef layer, SiwinWindowRef window);

void fig_draw_siwin_metal_layer_ref_set_opaque_binding(SiwinMetalLayerRef layer, bool opaque);

const char* fig_draw_siwin_backend_name_binding();

const char* fig_draw_siwin_window_title_binding(const char* suffix);

uint64_t fig_draw_shared_siwin_globals_ptr_binding();

SiwinRendererRef fig_draw_new_siwin_renderer_binding(int64_t atlas_size, float pixel_scale);

SiwinWindowRef fig_draw_new_siwin_window_binding(int32_t width, int32_t height, bool fullscreen, const char* title, bool vsync, int32_t msaa, bool resizable, bool frameless, bool transparent);

SiwinWindowRef fig_draw_new_siwin_window_for_renderer_binding(SiwinRendererRef renderer, int32_t width, int32_t height, bool fullscreen, const char* title, bool vsync, int32_t msaa, bool resizable, bool frameless, bool transparent);

SiwinMetalLayerRef fig_draw_attach_metal_layer_binding(SiwinWindowRef window, uint64_t device_ptr);

}

Fig::Fig() {
  this->reference = fig_draw_new_fig().reference;
}

void Fig::free(){
  fig_draw_fig_unref(*this);
}

Fig Fig::copy() {
  return fig_draw_fig_copy(*this);
};

FigKind Fig::kind() {
  return fig_draw_fig_kind(*this);
};

void Fig::setKind(FigKind kind) {
  fig_draw_fig_set_kind(*this, kind);
};

ZLevel Fig::zLevel() {
  return fig_draw_fig_z_level(*this);
};

void Fig::setZLevel(ZLevel zLevel) {
  fig_draw_fig_set_zlevel(*this, zLevel);
};

float Fig::x() {
  return fig_draw_fig_x(*this);
};

float Fig::y() {
  return fig_draw_fig_y(*this);
};

float Fig::width() {
  return fig_draw_fig_width(*this);
};

float Fig::height() {
  return fig_draw_fig_height(*this);
};

void Fig::setScreenBox(float x, float y, float w, float h) {
  fig_draw_fig_set_screen_box(*this, x, y, w, h);
};

void Fig::setFillColor(uint8_t r, uint8_t g, uint8_t b, uint8_t a) {
  fig_draw_fig_set_fill_color(*this, r, g, b, a);
};

void Fig::setRotation(float rotation) {
  fig_draw_fig_set_rotation(*this, rotation);
};

RenderList::RenderList() {
  this->reference = fig_draw_new_render_list().reference;
}

void RenderList::free(){
  fig_draw_render_list_unref(*this);
}

RenderList RenderList::copy() {
  return fig_draw_render_list_copy(*this);
};

void RenderList::clear() {
  fig_draw_render_list_clear(*this);
};

int64_t RenderList::nodeCount() {
  return fig_draw_render_list_node_count(*this);
};

int64_t RenderList::rootCount() {
  return fig_draw_render_list_root_count(*this);
};

int16_t RenderList::addRoot(Fig root) {
  return fig_draw_render_list_add_root(*this, root);
};

int16_t RenderList::addChild(int16_t parentIdx, Fig child) {
  return fig_draw_render_list_add_child(*this, parentIdx, child);
};

Fig RenderList::getNode(int16_t nodeIdx) {
  return fig_draw_render_list_get_node(*this, nodeIdx);
};

int16_t RenderList::getRootId(int16_t rootIdx) {
  return fig_draw_render_list_get_root_id(*this, rootIdx);
};

Renders::Renders() {
  this->reference = fig_draw_new_renders().reference;
}

void Renders::free(){
  fig_draw_renders_unref(*this);
}

void Renders::clear() {
  fig_draw_renders_clear(*this);
};

bool Renders::containsLayer(ZLevel zLevel) {
  return fig_draw_renders_contains_layer(*this, zLevel);
};

int16_t Renders::addRoot(ZLevel zLevel, Fig root) {
  return fig_draw_renders_add_root(*this, zLevel, root);
};

int16_t Renders::addChild(ZLevel zLevel, int16_t parentIdx, Fig child) {
  return fig_draw_renders_add_child(*this, zLevel, parentIdx, child);
};

int64_t Renders::layerNodeCount(ZLevel zLevel) {
  return fig_draw_renders_layer_node_count(*this, zLevel);
};

int64_t Renders::layerRootCount(ZLevel zLevel) {
  return fig_draw_renders_layer_root_count(*this, zLevel);
};

Fig Renders::getLayerNode(ZLevel zLevel, int16_t nodeIdx) {
  return fig_draw_renders_get_layer_node(*this, zLevel, nodeIdx);
};

Fig newRectangleFig(float x, float y, float w, float h) {
  return fig_draw_new_rectangle_fig(x, y, w, h);
};

Fig newTextFig(float x, float y, float w, float h) {
  return fig_draw_new_text_fig(x, y, w, h);
};

Fig newImageFig(float x, float y, float w, float h, int64_t imageId) {
  return fig_draw_new_image_fig(x, y, w, h, imageId);
};

Fig newTransformFig(float x, float y, float w, float h, float tx, float ty) {
  return fig_draw_new_transform_fig(x, y, w, h, tx, ty);
};

const char* figDataDir() {
  return fig_draw_fig_data_dir();
};

setFigDataDir(const char* dir) {
  fig_draw_set_fig_data_dir(dir);
};

float figUiScale() {
  return fig_draw_fig_ui_scale();
};

setFigUiScale(float scale) {
  fig_draw_set_fig_ui_scale(scale);
};

float scaled(float a) {
  return fig_draw_scaled(a);
};

float descaled(float a) {
  return fig_draw_descaled(a);
};

void SiwinWindowRef::free(){
  fig_draw_siwin_window_ref_unref(*this);
}

void SiwinWindowRef::closeWindowBinding() {
  fig_draw_siwin_window_ref_close_window_binding(*this);
};

void SiwinWindowRef::stepWindowBinding() {
  fig_draw_siwin_window_ref_step_window_binding(*this);
};

void SiwinWindowRef::makeCurrentWindowBinding() {
  fig_draw_siwin_window_ref_make_current_window_binding(*this);
};

bool SiwinWindowRef::windowIsOpenBinding() {
  return fig_draw_siwin_window_ref_window_is_open_binding(*this);
};

const char* SiwinWindowRef::siwinDisplayServerNameBinding() {
  return fig_draw_siwin_window_ref_siwin_display_server_name_binding(*this);
};

int32_t SiwinWindowRef::backingWidthBinding() {
  return fig_draw_siwin_window_ref_backing_width_binding(*this);
};

int32_t SiwinWindowRef::backingHeightBinding() {
  return fig_draw_siwin_window_ref_backing_height_binding(*this);
};

float SiwinWindowRef::logicalWidthBinding() {
  return fig_draw_siwin_window_ref_logical_width_binding(*this);
};

float SiwinWindowRef::logicalHeightBinding() {
  return fig_draw_siwin_window_ref_logical_height_binding(*this);
};

float SiwinWindowRef::contentScaleBinding() {
  return fig_draw_siwin_window_ref_content_scale_binding(*this);
};

bool SiwinWindowRef::configureUiScaleBinding(const char* envVar) {
  return fig_draw_siwin_window_ref_configure_ui_scale_binding(*this, envVar);
};

void SiwinWindowRef::refreshUiScaleBinding(bool autoScale) {
  fig_draw_siwin_window_ref_refresh_ui_scale_binding(*this, autoScale);
};

void SiwinWindowRef::presentNowBinding() {
  fig_draw_siwin_window_ref_present_now_binding(*this);
};

void SiwinRendererRef::free(){
  fig_draw_siwin_renderer_ref_unref(*this);
}

const char* SiwinRendererRef::siwinBackendNameForRendererBinding() {
  return fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(*this);
};

const char* SiwinRendererRef::siwinWindowTitleForRendererBinding(SiwinWindowRef window, const char* suffix) {
  return fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(*this, window, suffix);
};

void SiwinRendererRef::setupBackendBinding(SiwinWindowRef window) {
  fig_draw_siwin_renderer_ref_setup_backend_binding(*this, window);
};

void SiwinRendererRef::beginFrameBinding() {
  fig_draw_siwin_renderer_ref_begin_frame_binding(*this);
};

void SiwinRendererRef::endFrameBinding() {
  fig_draw_siwin_renderer_ref_end_frame_binding(*this);
};

void SiwinMetalLayerRef::free(){
  fig_draw_siwin_metal_layer_ref_unref(*this);
}

void SiwinMetalLayerRef::updateMetalLayerBinding(SiwinWindowRef window) {
  fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(*this, window);
};

void SiwinMetalLayerRef::setOpaqueBinding(bool opaque) {
  fig_draw_siwin_metal_layer_ref_set_opaque_binding(*this, opaque);
};

const char* siwinBackendNameBinding() {
  return fig_draw_siwin_backend_name_binding();
};

const char* siwinWindowTitleBinding(const char* suffix) {
  return fig_draw_siwin_window_title_binding(suffix);
};

uint64_t sharedSiwinGlobalsPtrBinding() {
  return fig_draw_shared_siwin_globals_ptr_binding();
};

SiwinRendererRef newSiwinRendererBinding(int64_t atlasSize, float pixelScale) {
  return fig_draw_new_siwin_renderer_binding(atlasSize, pixelScale);
};

SiwinWindowRef newSiwinWindowBinding(int32_t width, int32_t height, bool fullscreen, const char* title, bool vsync, int32_t msaa, bool resizable, bool frameless, bool transparent) {
  return fig_draw_new_siwin_window_binding(width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent);
};

SiwinWindowRef newSiwinWindowForRendererBinding(SiwinRendererRef renderer, int32_t width, int32_t height, bool fullscreen, const char* title, bool vsync, int32_t msaa, bool resizable, bool frameless, bool transparent) {
  return fig_draw_new_siwin_window_for_renderer_binding(renderer, width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent);
};

SiwinMetalLayerRef attachMetalLayerBinding(SiwinWindowRef window, uint64_t devicePtr) {
  return fig_draw_attach_metal_layer_binding(window, devicePtr);
};

#endif
