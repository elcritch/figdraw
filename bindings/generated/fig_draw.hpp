#ifndef INCLUDE_FIGDRAW_H
#define INCLUDE_FIGDRAW_H

#include <stdint.h>

typedef char FigKind;
#define FIG_KIND 0

struct Fig;

struct RenderList;

struct Renders;

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

const char* fig_draw_siwin_backend_name_binding();

const char* fig_draw_siwin_window_title_binding(const char* suffix);

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

const char* siwinBackendNameBinding() {
  return fig_draw_siwin_backend_name_binding();
};

const char* siwinWindowTitleBinding(const char* suffix) {
  return fig_draw_siwin_window_title_binding(suffix);
};

#endif
