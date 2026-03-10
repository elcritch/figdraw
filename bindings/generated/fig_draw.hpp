#ifndef INCLUDE_FIGDRAW_H
#define INCLUDE_FIGDRAW_H

#include <stdint.h>

extern "C" {

const char* fig_draw_fig_data_dir();

void fig_draw_set_fig_data_dir(const char* dir);

float fig_draw_fig_ui_scale();

void fig_draw_set_fig_ui_scale(float scale);

float fig_draw_scaled(float a);

float fig_draw_descaled(float a);

}

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

#endif
