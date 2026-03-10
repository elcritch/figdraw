#ifndef INCLUDE_FIGDRAW_H
#define INCLUDE_FIGDRAW_H

typedef char FigKind;
#define FIG_KIND 0

typedef long long Fig;

typedef long long RenderList;

typedef long long Renders;

typedef long long SiwinWindowRef;

typedef long long SiwinRendererRef;

typedef long long SiwinMetalLayerRef;

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

void fig_draw_fig_set_fill_color(Fig fig, unsigned char r, unsigned char g, unsigned char b, unsigned char a);

void fig_draw_fig_set_rotation(Fig fig, float rotation);

void fig_draw_render_list_unref(RenderList render_list);

RenderList fig_draw_new_render_list();

RenderList fig_draw_render_list_copy(RenderList list);

void fig_draw_render_list_clear(RenderList list);

long long fig_draw_render_list_node_count(RenderList list);

long long fig_draw_render_list_root_count(RenderList list);

short fig_draw_render_list_add_root(RenderList list, Fig root);

short fig_draw_render_list_add_child(RenderList list, short parent_idx, Fig child);

Fig fig_draw_render_list_get_node(RenderList list, short node_idx);

short fig_draw_render_list_get_root_id(RenderList list, short root_idx);

void fig_draw_renders_unref(Renders renders);

Renders fig_draw_new_renders();

void fig_draw_renders_clear(Renders renders);

char fig_draw_renders_contains_layer(Renders renders, ZLevel z_level);

short fig_draw_renders_add_root(Renders renders, ZLevel z_level, Fig root);

short fig_draw_renders_add_child(Renders renders, ZLevel z_level, short parent_idx, Fig child);

long long fig_draw_renders_layer_node_count(Renders renders, ZLevel z_level);

long long fig_draw_renders_layer_root_count(Renders renders, ZLevel z_level);

Fig fig_draw_renders_get_layer_node(Renders renders, ZLevel z_level, short node_idx);

Fig fig_draw_new_rectangle_fig(float x, float y, float w, float h);

Fig fig_draw_new_text_fig(float x, float y, float w, float h);

Fig fig_draw_new_image_fig(float x, float y, float w, float h, long long image_id);

Fig fig_draw_new_transform_fig(float x, float y, float w, float h, float tx, float ty);

char* fig_draw_fig_data_dir();

void fig_draw_set_fig_data_dir(char* dir);

float fig_draw_fig_ui_scale();

void fig_draw_set_fig_ui_scale(float scale);

float fig_draw_scaled(float a);

float fig_draw_descaled(float a);

void fig_draw_siwin_window_ref_unref(SiwinWindowRef siwin_window_ref);

void fig_draw_siwin_window_ref_close_window_binding(SiwinWindowRef window);

void fig_draw_siwin_window_ref_step_window_binding(SiwinWindowRef window);

void fig_draw_siwin_window_ref_make_current_window_binding(SiwinWindowRef window);

char fig_draw_siwin_window_ref_window_is_open_binding(SiwinWindowRef window);

char* fig_draw_siwin_window_ref_siwin_display_server_name_binding(SiwinWindowRef window);

int fig_draw_siwin_window_ref_backing_width_binding(SiwinWindowRef window);

int fig_draw_siwin_window_ref_backing_height_binding(SiwinWindowRef window);

float fig_draw_siwin_window_ref_logical_width_binding(SiwinWindowRef window);

float fig_draw_siwin_window_ref_logical_height_binding(SiwinWindowRef window);

float fig_draw_siwin_window_ref_content_scale_binding(SiwinWindowRef window);

char fig_draw_siwin_window_ref_configure_ui_scale_binding(SiwinWindowRef window, char* env_var);

void fig_draw_siwin_window_ref_refresh_ui_scale_binding(SiwinWindowRef window, char auto_scale);

void fig_draw_siwin_window_ref_present_now_binding(SiwinWindowRef window);

void fig_draw_siwin_renderer_ref_unref(SiwinRendererRef siwin_renderer_ref);

char* fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(SiwinRendererRef renderer);

char* fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(SiwinRendererRef renderer, SiwinWindowRef window, char* suffix);

void fig_draw_siwin_renderer_ref_setup_backend_binding(SiwinRendererRef renderer, SiwinWindowRef window);

void fig_draw_siwin_renderer_ref_begin_frame_binding(SiwinRendererRef renderer);

void fig_draw_siwin_renderer_ref_end_frame_binding(SiwinRendererRef renderer);

void fig_draw_siwin_metal_layer_ref_unref(SiwinMetalLayerRef siwin_metal_layer_ref);

void fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(SiwinMetalLayerRef layer, SiwinWindowRef window);

void fig_draw_siwin_metal_layer_ref_set_opaque_binding(SiwinMetalLayerRef layer, char opaque);

char* fig_draw_siwin_backend_name_binding();

char* fig_draw_siwin_window_title_binding(char* suffix);

unsigned long long fig_draw_shared_siwin_globals_ptr_binding();

SiwinRendererRef fig_draw_new_siwin_renderer_binding(long long atlas_size, float pixel_scale);

SiwinWindowRef fig_draw_new_siwin_window_binding(int width, int height, char fullscreen, char* title, char vsync, int msaa, char resizable, char frameless, char transparent);

SiwinWindowRef fig_draw_new_siwin_window_for_renderer_binding(SiwinRendererRef renderer, int width, int height, char fullscreen, char* title, char vsync, int msaa, char resizable, char frameless, char transparent);

SiwinMetalLayerRef fig_draw_attach_metal_layer_binding(SiwinWindowRef window, unsigned long long device_ptr);

#endif
