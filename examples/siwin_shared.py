#!/usr/bin/env python3

import math
import os
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
GENERATED_DIR = ROOT / "src" / "figdraw" / "bindings" / "generated"
sys.path.insert(0, str(GENERATED_DIR))

import figdraw as fd


COPIES = int(os.environ.get("FIGDRAW_COPIES", "100"))
RUN_ONCE = os.environ.get("FIGDRAW_RUN_ONCE", "").lower() in ("1", "true", "yes", "on")
NO_SLEEP = os.environ.get("FIGDRAW_NO_SLEEP", "1").lower() in ("1", "true", "yes", "on")
TRACE_SHARED = os.environ.get("FIGDRAW_TRACE_SHARED", "").lower() in (
    "1",
    "true",
    "yes",
    "on",
)


RED_FILL = fd.ColorRGBA(220, 40, 40, 155)
RED_STROKE = fd.ColorRGBA(0, 0, 0, 155)
GREEN_SOLID = fd.ColorRGBA(40, 180, 90, 155)
GREEN_GRAD_START = fd.ColorRGBA(18, 112, 64, 255)
GREEN_GRAD_MID = fd.ColorRGBA(40, 180, 90, 255)
GREEN_GRAD_STOP = fd.ColorRGBA(78, 224, 188, 255)
BLUE_SOLID = fd.ColorRGBA(60, 90, 220, 155)
BLUE_GRAD_START = fd.ColorRGBA(44, 72, 186, 255)
BLUE_GRAD_MID = fd.ColorRGBA(60, 90, 220, 255)
BLUE_GRAD_STOP = fd.ColorRGBA(118, 168, 255, 255)
WHITE_STROKE = fd.ColorRGBA(255, 255, 255, 210)
BLACK_SHADOW = fd.ColorRGBA(0, 0, 0, 155)
BLUE_INNER_SHADOW = fd.ColorRGBA(40, 40, 60, 150)
RED_BORDER = 5.0
BLUE_BORDER = 4.0


def fract(x):
    return x - math.floor(x)


def trace(message):
    if TRACE_SHARED:
        print(f"trace: {message}", flush=True)


def require_ref(value, message):
    if getattr(value, "ref", 0) == 0:
        raise RuntimeError(message)
    return value


def build_render_tree(renders, width, height, frame):
    renders.clear()
    t = frame * 0.02

    background = require_ref(
        fd.new_rectangle_fig(0.0, 0.0, width, height),
        "makeRenderTree: newRectangleFig returned nil",
    )
    background.set_fill_color_rgba(fd.ColorRGBA(255, 255, 255, 155))
    renders.add_root(0, background)

    red_start_x = 60.0
    red_start_y = 60.0
    green_start_x = 320.0
    green_start_y = 120.0
    blue_start_x = 180.0
    blue_start_y = 300.0
    max_w = 260.0
    max_h = 180.0
    max_x = max(0.0, width - (green_start_x + max_w))
    max_y = max(0.0, height - (blue_start_y + max_h))

    loop_copies = 1 if TRACE_SHARED else COPIES
    for i in range(loop_copies):
        if TRACE_SHARED and i == 0:
            trace("loop i=0 start")

        seed_x = math.sin(i * 78.233) * 43758.5453
        seed_y = math.sin((i + 19) * 37.719) * 24634.6345
        base_x = fract(seed_x) * max_x if max_x > 0.0 else 0.0
        base_y = fract(seed_y) * max_y if max_y > 0.0 else 0.0
        jitter_x = math.sin(t + i * 0.15) * 20.0
        jitter_y = math.cos(t * 0.9 + i * 0.2) * 20.0
        offset_x = min(max(base_x + jitter_x, 0.0), max_x)
        offset_y = min(max(base_y + jitter_y, 0.0), max_y)
        size_pulse_w = 0.5 + 0.5 * math.sin(t * 0.8 + i * 0.07)
        size_pulse_h = 0.5 + 0.5 * math.cos(t * 0.65 + i * 0.09)
        red_w = 160.0 + 100.0 * size_pulse_w
        red_h = 110.0 + 70.0 * size_pulse_h
        green_w = 160.0 + 100.0 * size_pulse_h
        green_h = 110.0 + 70.0 * size_pulse_w
        blue_w = 160.0 + 100.0 * (1.0 - size_pulse_w)
        blue_h = 110.0 + 70.0 * (1.0 - size_pulse_h)

        red_fig = require_ref(
            fd.new_rectangle_fig(
                red_start_x + offset_x, red_start_y + offset_y, red_w, red_h
            ),
            "newRectangleFig returned nil for red fig",
        )
        red_fig.set_fill_color_rgba(RED_FILL)
        corner_pulse = 0.5 + 0.5 * math.sin(t * 1.25 + i * 0.11)
        c0 = 4.0 + 26.0 * corner_pulse
        c1 = 6.0 + 22.0 * (1.0 - corner_pulse)
        c2 = 8.0 + 18.0 * (0.5 + 0.5 * math.sin(t * 0.7 + i * 0.05))
        c3 = 10.0 + 16.0 * (0.5 + 0.5 * math.cos(t * 0.8 + i * 0.06))
        if not TRACE_SHARED:
            red_fig.set_corners(fd.CornerRadii(c0, c1, c2, c3))
            red_fig.set_stroke(RED_BORDER, RED_STROKE)
        renders.add_root(0, red_fig)

        green_fig = require_ref(
            fd.new_rectangle_fig(
                green_start_x + offset_x,
                green_start_y + offset_y,
                green_w,
                green_h,
            ),
            "newRectangleFig returned nil for green fig",
        )
        if not TRACE_SHARED and i % 2 == 0:
            axis = fd.FGA_X if (i % 4) < 2 else fd.FGA_DIAG_TLBR
            green_fig.set_fill_linear3(
                GREEN_GRAD_START, GREEN_GRAD_MID, GREEN_GRAD_STOP, axis, 128
            )
        else:
            green_fig.set_fill_color_rgba(GREEN_SOLID)

        green_corner_pulse = 0.5 + 0.5 * math.cos(t * 0.95 + i * 0.08)
        g0 = 6.0 + 22.0 * green_corner_pulse
        g1 = 8.0 + 18.0 * (1.0 - green_corner_pulse)
        g2 = 10.0 + 16.0 * (0.5 + 0.5 * math.cos(t * 0.75 + i * 0.04))
        g3 = 12.0 + 14.0 * (0.5 + 0.5 * math.sin(t * 0.85 + i * 0.05))
        shadow_pulse = 0.5 + 0.5 * math.sin(t * 1.1 + i * 0.05)
        shadow_blur = max(0.0, 6.0 + 18.0 * shadow_pulse)
        shadow_spread = max(0.0, 4.0 + 20.0 * (1.0 - shadow_pulse))
        shadow_x = 6.0 + 10.0 * math.sin(t * 0.9 + i * 0.03)
        shadow_y = 6.0 + 10.0 * math.cos(t * 0.9 + i * 0.03)
        if not TRACE_SHARED:
            green_fig.set_corners(fd.CornerRadii(g0, g1, g2, g3))
            green_fig.clear_shadows()
            green_fig.set_shadow(
                0,
                fd.DROP_SHADOW,
                shadow_blur,
                shadow_spread,
                shadow_x,
                shadow_y,
                BLACK_SHADOW,
            )
        renders.add_root(0, green_fig)

        blue_fig = require_ref(
            fd.new_rectangle_fig(
                blue_start_x + offset_x, blue_start_y + offset_y, blue_w, blue_h
            ),
            "newRectangleFig returned nil for blue fig",
        )
        if not TRACE_SHARED and i % 3 == 0:
            axis = fd.FGA_Y if (i % 2) == 0 else fd.FGA_DIAG_BLTR
            blue_fig.set_fill_linear3(
                BLUE_GRAD_START, BLUE_GRAD_MID, BLUE_GRAD_STOP, axis, 132
            )
        else:
            blue_fig.set_fill_color_rgba(BLUE_SOLID)

        inset_pulse = 0.5 + 0.5 * math.sin(t * 1.05 + i * 0.06)
        inset_blur = max(0.0, 8.0 + 10.0 * inset_pulse)
        inset_spread = max(0.0, 2.0 + 10.0 * (1.0 - inset_pulse))
        inset_x = 6.0 * math.sin(t * 0.85 + i * 0.04)
        inset_y = 6.0 * math.cos(t * 0.8 + i * 0.04)
        if not TRACE_SHARED:
            blue_fig.set_stroke(BLUE_BORDER, WHITE_STROKE)
            blue_fig.clear_shadows()
            blue_fig.set_shadow(
                0,
                fd.INNER_SHADOW,
                inset_blur,
                inset_spread,
                inset_x,
                inset_y,
                BLUE_INNER_SHADOW,
            )
        renders.add_root(0, blue_fig)


def main():
    fd.set_fig_data_dir(str(ROOT / "data"))

    typeface = require_ref(
        fd.load_typeface_binding("Ubuntu.ttf"), "Failed to load typeface: Ubuntu.ttf"
    )
    fps_font = require_ref(fd.FigFontRef(typeface, 18.0), "Failed to create fps font")
    fps_text = "0.0 FPS"

    app = require_ref(
        fd.FigSiwinAppRef(
            800,
            600,
            "Siwin RenderList (Python Shared Lib)",
            512,
            1.0,
            False,
            True,
            0,
            True,
            False,
            False,
        ),
        "Failed to create siwin app",
    )
    trace(
        "created siwin app backend="
        + app.siwin_backend_name()
        + " display="
        + app.siwin_display_server_name()
    )
    app.siwin_first_step()

    renders = require_ref(fd.Renders(), "Failed to create renders")

    app_running = True
    global_frame = 0
    frames = 0
    fps_frames = 0
    fps_start = time.time()
    make_render_tree_us_sum = 0.0
    render_frame_us_sum = 0.0
    last_element_count = 0

    try:
        while app.siwin_opened() and app_running:
            app.siwin_refresh_ui_scale()
            frames += 1
            global_frame += 1
            fps_frames += 1

            size = app.siwin_window_size()
            width = float(size.w)
            height = float(size.h)

            t0 = time.perf_counter()
            build_render_tree(renders, width, height, global_frame)
            make_render_tree_us_sum += (time.perf_counter() - t0) * 1_000_000.0
            last_element_count = renders.layer_node_count(0)

            hud_margin = 12.0
            hud_w = 180.0
            hud_h = 34.0
            hud_x = width - hud_w - hud_margin
            hud_y = hud_margin
            hud_rect = require_ref(
                fd.new_rectangle_fig(hud_x, hud_y, hud_w, hud_h),
                "Failed to create HUD rect",
            )
            hud_rect.set_fill_color_rgba(fd.ColorRGBA(0, 0, 0, 155))
            hud_rect.set_corners(fd.CornerRadii(8, 8, 8, 8))
            renders.add_root(0, hud_rect)

            hud_text_pad_x = 10.0
            hud_text_pad_y = 6.0
            hud_text_x = hud_x + hud_text_pad_x
            hud_text_y = hud_y + hud_text_pad_y
            hud_text_w = hud_w - hud_text_pad_x * 2.0
            hud_text_h = hud_h - hud_text_pad_y * 2.0
            fps_layout = fd.typeset_text_binding(
                hud_text_w,
                hud_text_h,
                fps_font,
                fps_text,
                2,
                1,
                False,
                False,
            )
            if getattr(fps_layout, "ref", 0) != 0:
                hud_text = require_ref(
                    fd.new_text_fig(hud_text_x, hud_text_y, hud_text_w, hud_text_h),
                    "Failed to create HUD text",
                )
                hud_text.set_fill_color_rgba(fd.ColorRGBA(0, 0, 0, 0))
                fd.set_fig_text_layout_binding(hud_text, fps_layout)
                renders.add_root(0, hud_text)

            t1 = time.perf_counter()
            app.render_siwin_frame_binding(renders, width, height)
            render_frame_us_sum += (time.perf_counter() - t1) * 1_000_000.0
            app.siwin_redraw()
            app.siwin_step()

            now = time.time()
            elapsed = now - fps_start
            if elapsed >= 1.0:
                fps = fps_frames / elapsed
                fps_text = f"{fps:.1f} FPS"
                avg_make = make_render_tree_us_sum / max(1, fps_frames)
                avg_render = render_frame_us_sum / max(1, fps_frames)
                print(
                    "fps: "
                    f"{fps} | elems: {last_element_count}"
                    f" | makeRenderTree avg(us): {avg_make}"
                    f" | renderFrame avg(us): {avg_render}",
                    flush=True,
                )
                fps_frames = 0
                fps_start = now
                make_render_tree_us_sum = 0.0
                render_frame_us_sum = 0.0

            if RUN_ONCE and frames >= 1:
                app_running = False

            if not NO_SLEEP and app_running:
                time.sleep(0.016)
    finally:
        if not TRACE_SHARED:
            app.siwin_close()


if __name__ == "__main__":
    main()
