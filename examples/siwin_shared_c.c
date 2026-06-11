#include "../src/figdraw/bindings/generated/figdraw.h"

#include <math.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

#ifdef _WIN32
#include <windows.h>
static void sleep_ms(int ms) { Sleep((DWORD)ms); }
#else
#include <unistd.h>
static void sleep_ms(int ms) { usleep((useconds_t)ms * 1000); }
#endif

#ifndef FIGDRAW_COPIES
#define FIGDRAW_COPIES 100
#endif

static const float RED_BORDER = 5.0f;
static const float BLUE_BORDER = 4.0f;

static ColorRGBA RED_FILL = {220, 40, 40, 155};
static ColorRGBA RED_STROKE = {0, 0, 0, 155};
static ColorRGBA GREEN_SOLID = {40, 180, 90, 155};
static ColorRGBA GREEN_GRAD_START = {18, 112, 64, 255};
static ColorRGBA GREEN_GRAD_MID = {40, 180, 90, 255};
static ColorRGBA GREEN_GRAD_STOP = {78, 224, 188, 255};
static ColorRGBA BLUE_SOLID = {60, 90, 220, 155};
static ColorRGBA BLUE_GRAD_START = {44, 72, 186, 255};
static ColorRGBA BLUE_GRAD_MID = {60, 90, 220, 255};
static ColorRGBA BLUE_GRAD_STOP = {118, 168, 255, 255};
static ColorRGBA WHITE_STROKE = {255, 255, 255, 210};
static ColorRGBA BLACK_SHADOW = {0, 0, 0, 155};
static ColorRGBA BLUE_INNER_SHADOW = {40, 40, 60, 150};

static double now_seconds(void) {
  struct timespec ts;
#ifdef CLOCK_MONOTONIC
  clock_gettime(CLOCK_MONOTONIC, &ts);
#else
  timespec_get(&ts, TIME_UTC);
#endif
  return (double)ts.tv_sec + (double)ts.tv_nsec / 1000000000.0;
}

static float fractf_local(float x) { return x - floorf(x); }

static int env_enabled(const char *name, int default_value) {
  const char *value = getenv(name);
  if (value == NULL || value[0] == '\0') {
    return default_value;
  }
  return strcmp(value, "1") == 0 || strcmp(value, "true") == 0 ||
         strcmp(value, "yes") == 0 || strcmp(value, "on") == 0;
}

static char *take_error_string(void) {
  GennyBuffer buffer = figdraw_take_error();
  intptr_t len = figdraw_genny_buffer_len(buffer);
  const char *data = figdraw_genny_buffer_data(buffer);
  char *result = (char *)calloc((size_t)len + 1, 1);
  if (result != NULL && data != NULL && len > 0) {
    memcpy(result, data, (size_t)len);
  }
  figdraw_genny_buffer_unref(buffer);
  return result;
}

static int check_figdraw_error(const char *context) {
  if (!figdraw_check_error()) {
    return 0;
  }
  char *message = take_error_string();
  fprintf(stderr, "%s: %s\n", context, message != NULL ? message : "unknown error");
  free(message);
  return 1;
}

static char *buffer_to_string(GennyBuffer buffer) {
  intptr_t len = figdraw_genny_buffer_len(buffer);
  const char *data = figdraw_genny_buffer_data(buffer);
  char *result = (char *)calloc((size_t)len + 1, 1);
  if (result != NULL && data != NULL && len > 0) {
    memcpy(result, data, (size_t)len);
  }
  figdraw_genny_buffer_unref(buffer);
  return result;
}

static int add_root_checked(Renders renders, FigRef fig) {
  figdraw_renders_add_root(renders, 0, fig);
  if (check_figdraw_error("figdraw_renders_add_root")) {
    return 1;
  }
  return 0;
}

static int build_render_tree(Renders renders, float width, float height, int frame) {
  figdraw_renders_clear(renders);
  float t = (float)frame * 0.02f;

  FigRef background = figdraw_new_rectangle_fig(0.0f, 0.0f, width, height);
  if (background == NULL) {
    fprintf(stderr, "new background fig failed\n");
    return 1;
  }
  figdraw_fig_ref_set_fill_color_rgba(background, (ColorRGBA){255, 255, 255, 155});
  if (add_root_checked(renders, background)) {
    figdraw_fig_ref_unref(background);
    return 1;
  }
  figdraw_fig_ref_unref(background);

  const float red_start_x = 60.0f;
  const float red_start_y = 60.0f;
  const float green_start_x = 320.0f;
  const float green_start_y = 120.0f;
  const float blue_start_x = 180.0f;
  const float blue_start_y = 300.0f;
  const float max_w = 260.0f;
  const float max_h = 180.0f;
  const float max_x = fmaxf(0.0f, width - (green_start_x + max_w));
  const float max_y = fmaxf(0.0f, height - (blue_start_y + max_h));

  for (int i = 0; i < FIGDRAW_COPIES; i++) {
    float seed_x = sinf((float)i * 78.233f) * 43758.5453f;
    float seed_y = sinf((float)(i + 19) * 37.719f) * 24634.6345f;
    float base_x = max_x > 0.0f ? fractf_local(seed_x) * max_x : 0.0f;
    float base_y = max_y > 0.0f ? fractf_local(seed_y) * max_y : 0.0f;
    float jitter_x = sinf(t + (float)i * 0.15f) * 20.0f;
    float jitter_y = cosf(t * 0.9f + (float)i * 0.2f) * 20.0f;
    float offset_x = fminf(fmaxf(base_x + jitter_x, 0.0f), max_x);
    float offset_y = fminf(fmaxf(base_y + jitter_y, 0.0f), max_y);
    float size_pulse_w = 0.5f + 0.5f * sinf(t * 0.8f + (float)i * 0.07f);
    float size_pulse_h = 0.5f + 0.5f * cosf(t * 0.65f + (float)i * 0.09f);
    float red_w = 160.0f + 100.0f * size_pulse_w;
    float red_h = 110.0f + 70.0f * size_pulse_h;
    float green_w = 160.0f + 100.0f * size_pulse_h;
    float green_h = 110.0f + 70.0f * size_pulse_w;
    float blue_w = 160.0f + 100.0f * (1.0f - size_pulse_w);
    float blue_h = 110.0f + 70.0f * (1.0f - size_pulse_h);

    FigRef red = figdraw_new_rectangle_fig(
        red_start_x + offset_x, red_start_y + offset_y, red_w, red_h);
    figdraw_fig_ref_set_fill_color_rgba(red, RED_FILL);
    float corner_pulse = 0.5f + 0.5f * sinf(t * 1.25f + (float)i * 0.11f);
    figdraw_fig_ref_set_corners(
        red,
        figdraw_corner_radii(
            4.0f + 26.0f * corner_pulse,
            6.0f + 22.0f * (1.0f - corner_pulse),
            8.0f + 18.0f * (0.5f + 0.5f * sinf(t * 0.7f + (float)i * 0.05f)),
            10.0f + 16.0f * (0.5f + 0.5f * cosf(t * 0.8f + (float)i * 0.06f))));
    figdraw_fig_ref_set_stroke(red, RED_BORDER, RED_STROKE);
    if (add_root_checked(renders, red)) {
      figdraw_fig_ref_unref(red);
      return 1;
    }
    figdraw_fig_ref_unref(red);

    FigRef green = figdraw_new_rectangle_fig(
        green_start_x + offset_x, green_start_y + offset_y, green_w, green_h);
    if ((i % 2) == 0) {
      FillGradientAxis axis = (i % 4) < 2 ? FGA_X : FGA_DIAG_TLBR;
      figdraw_fig_ref_set_fill_linear3(
          green, GREEN_GRAD_START, GREEN_GRAD_MID, GREEN_GRAD_STOP, axis, 128);
    } else {
      figdraw_fig_ref_set_fill_color_rgba(green, GREEN_SOLID);
    }
    float green_corner_pulse = 0.5f + 0.5f * cosf(t * 0.95f + (float)i * 0.08f);
    figdraw_fig_ref_set_corners(
        green,
        figdraw_corner_radii(
            6.0f + 22.0f * green_corner_pulse,
            8.0f + 18.0f * (1.0f - green_corner_pulse),
            10.0f + 16.0f * (0.5f + 0.5f * cosf(t * 0.75f + (float)i * 0.04f)),
            12.0f + 14.0f * (0.5f + 0.5f * sinf(t * 0.85f + (float)i * 0.05f))));
    float shadow_pulse = 0.5f + 0.5f * sinf(t * 1.1f + (float)i * 0.05f);
    figdraw_fig_ref_clear_shadows(green);
    figdraw_fig_ref_set_shadow(
        green, 0, DROP_SHADOW,
        fmaxf(0.0f, 6.0f + 18.0f * shadow_pulse),
        fmaxf(0.0f, 4.0f + 20.0f * (1.0f - shadow_pulse)),
        6.0f + 10.0f * sinf(t * 0.9f + (float)i * 0.03f),
        6.0f + 10.0f * cosf(t * 0.9f + (float)i * 0.03f),
        BLACK_SHADOW);
    if (add_root_checked(renders, green)) {
      figdraw_fig_ref_unref(green);
      return 1;
    }
    figdraw_fig_ref_unref(green);

    FigRef blue = figdraw_new_rectangle_fig(
        blue_start_x + offset_x, blue_start_y + offset_y, blue_w, blue_h);
    if ((i % 3) == 0) {
      FillGradientAxis axis = (i % 2) == 0 ? FGA_Y : FGA_DIAG_BLTR;
      figdraw_fig_ref_set_fill_linear3(
          blue, BLUE_GRAD_START, BLUE_GRAD_MID, BLUE_GRAD_STOP, axis, 132);
    } else {
      figdraw_fig_ref_set_fill_color_rgba(blue, BLUE_SOLID);
    }
    figdraw_fig_ref_set_stroke(blue, BLUE_BORDER, WHITE_STROKE);
    float inset_pulse = 0.5f + 0.5f * sinf(t * 1.05f + (float)i * 0.06f);
    figdraw_fig_ref_clear_shadows(blue);
    figdraw_fig_ref_set_shadow(
        blue, 0, INNER_SHADOW,
        fmaxf(0.0f, 8.0f + 10.0f * inset_pulse),
        fmaxf(0.0f, 2.0f + 10.0f * (1.0f - inset_pulse)),
        6.0f * sinf(t * 0.85f + (float)i * 0.04f),
        6.0f * cosf(t * 0.8f + (float)i * 0.04f),
        BLUE_INNER_SHADOW);
    if (add_root_checked(renders, blue)) {
      figdraw_fig_ref_unref(blue);
      return 1;
    }
    figdraw_fig_ref_unref(blue);
  }
  return 0;
}

int main(void) {
  figdraw_set_fig_data_dir("data");

  TypefaceRef typeface = figdraw_load_typeface_binding("Ubuntu.ttf");
  if (check_figdraw_error("figdraw_load_typeface_binding") || typeface == NULL) {
    return 1;
  }
  FigFontRef fps_font = figdraw_new_fig_font_binding(typeface, 18.0f);
  if (fps_font == NULL) {
    fprintf(stderr, "Failed to create fps font\n");
    return 1;
  }

  FigSiwinAppRef app = figdraw_new_fig_siwin_app_binding(
      800, 600, "Siwin RenderList (C Shared Lib)", 512, 1.0f,
      0, 1, 0, 1, 0, 0);
  if (check_figdraw_error("figdraw_new_fig_siwin_app_binding") || app == NULL) {
    return 1;
  }

  char *backend = buffer_to_string(figdraw_fig_siwin_app_ref_siwin_backend_name(app));
  char *display =
      buffer_to_string(figdraw_fig_siwin_app_ref_siwin_display_server_name(app));
  printf("backend=%s display=%s\n", backend != NULL ? backend : "",
         display != NULL ? display : "");
  free(backend);
  free(display);

  figdraw_fig_siwin_app_ref_siwin_first_step(app);
  if (check_figdraw_error("figdraw_fig_siwin_app_ref_siwin_first_step")) {
    return 1;
  }

  Renders renders = figdraw_new_renders();
  if (renders == NULL) {
    fprintf(stderr, "Failed to create renders\n");
    return 1;
  }

  int frames = 0;
  int fps_frames = 0;
  int global_frame = 0;
  double fps_start = now_seconds();
  double make_sum_us = 0.0;
  double render_sum_us = 0.0;
  intptr_t last_element_count = 0;
  char fps_text[64] = "0.0 FPS";
  int run_once = env_enabled("FIGDRAW_RUN_ONCE", 0);
  int no_sleep = env_enabled("FIGDRAW_NO_SLEEP", 1);

  while (figdraw_fig_siwin_app_ref_siwin_opened(app)) {
    if (check_figdraw_error("figdraw_fig_siwin_app_ref_siwin_opened")) {
      return 1;
    }
    figdraw_fig_siwin_app_ref_siwin_refresh_ui_scale(app);
    if (check_figdraw_error("figdraw_fig_siwin_app_ref_siwin_refresh_ui_scale")) {
      return 1;
    }

    frames++;
    fps_frames++;
    global_frame++;

    WindowSize size = figdraw_fig_siwin_app_ref_siwin_window_size(app);
    if (check_figdraw_error("figdraw_fig_siwin_app_ref_siwin_window_size")) {
      return 1;
    }
    float width = (float)size.w;
    float height = (float)size.h;

    double t0 = now_seconds();
    if (build_render_tree(renders, width, height, global_frame)) {
      return 1;
    }
    make_sum_us += (now_seconds() - t0) * 1000000.0;
    last_element_count = figdraw_renders_layer_node_count(renders, 0);
    if (check_figdraw_error("figdraw_renders_layer_node_count")) {
      return 1;
    }

    float hud_margin = 12.0f;
    float hud_w = 180.0f;
    float hud_h = 34.0f;
    float hud_x = width - hud_w - hud_margin;
    float hud_y = hud_margin;
    FigRef hud_rect = figdraw_new_rectangle_fig(hud_x, hud_y, hud_w, hud_h);
    figdraw_fig_ref_set_fill_color_rgba(hud_rect, (ColorRGBA){0, 0, 0, 155});
    figdraw_fig_ref_set_corners(hud_rect, figdraw_corner_radii(8, 8, 8, 8));
    if (add_root_checked(renders, hud_rect)) {
      figdraw_fig_ref_unref(hud_rect);
      return 1;
    }
    figdraw_fig_ref_unref(hud_rect);

    float text_x = hud_x + 10.0f;
    float text_y = hud_y + 6.0f;
    float text_w = hud_w - 20.0f;
    float text_h = hud_h - 12.0f;
    GlyphLayoutRef fps_layout = figdraw_typeset_text_binding(
        text_w, text_h, fps_font, fps_text, 2, 1, 0, 0);
    if (check_figdraw_error("figdraw_typeset_text_binding")) {
      return 1;
    }
    if (fps_layout != NULL) {
      FigRef hud_text = figdraw_new_text_fig(text_x, text_y, text_w, text_h);
      figdraw_fig_ref_set_fill_color_rgba(hud_text, (ColorRGBA){0, 0, 0, 0});
      figdraw_set_fig_text_layout_binding(hud_text, fps_layout);
      if (check_figdraw_error("figdraw_set_fig_text_layout_binding")) {
        figdraw_fig_ref_unref(hud_text);
        figdraw_glyph_layout_ref_unref(fps_layout);
        return 1;
      }
      if (add_root_checked(renders, hud_text)) {
        figdraw_fig_ref_unref(hud_text);
        figdraw_glyph_layout_ref_unref(fps_layout);
        return 1;
      }
      figdraw_fig_ref_unref(hud_text);
      figdraw_glyph_layout_ref_unref(fps_layout);
    }

    double t1 = now_seconds();
    figdraw_fig_siwin_app_ref_render_siwin_frame_binding(app, renders, width, height);
    if (check_figdraw_error("figdraw_fig_siwin_app_ref_render_siwin_frame_binding")) {
      return 1;
    }
    render_sum_us += (now_seconds() - t1) * 1000000.0;
    figdraw_fig_siwin_app_ref_siwin_redraw(app);
    if (check_figdraw_error("figdraw_fig_siwin_app_ref_siwin_redraw")) {
      return 1;
    }
    figdraw_fig_siwin_app_ref_siwin_step(app);
    if (check_figdraw_error("figdraw_fig_siwin_app_ref_siwin_step")) {
      return 1;
    }

    double now = now_seconds();
    double elapsed = now - fps_start;
    if (elapsed >= 1.0) {
      double fps = (double)fps_frames / elapsed;
      snprintf(fps_text, sizeof(fps_text), "%.1f FPS", fps);
      printf("fps: %f | elems: %ld | makeRenderTree avg(us): %f | "
             "renderFrame avg(us): %f\n",
             fps, (long)last_element_count, make_sum_us / (double)fps_frames,
             render_sum_us / (double)fps_frames);
      fflush(stdout);
      fps_frames = 0;
      fps_start = now;
      make_sum_us = 0.0;
      render_sum_us = 0.0;
    }

    if (run_once && frames >= 1) {
      break;
    }
    if (!no_sleep) {
      sleep_ms(16);
    }
  }

  figdraw_fig_siwin_app_ref_siwin_close(app);
  figdraw_renders_unref(renders);
  figdraw_fig_siwin_app_ref_unref(app);
  figdraw_fig_font_ref_unref(fps_font);
  figdraw_typeface_ref_unref(typeface);
  return 0;
}
