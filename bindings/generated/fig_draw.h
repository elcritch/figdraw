#ifndef INCLUDE_FIGDRAW_H
#define INCLUDE_FIGDRAW_H

char* fig_draw_fig_data_dir();

void fig_draw_set_fig_data_dir(char* dir);

float fig_draw_fig_ui_scale();

void fig_draw_set_fig_ui_scale(float scale);

float fig_draw_scaled(float a);

float fig_draw_descaled(float a);

#endif
