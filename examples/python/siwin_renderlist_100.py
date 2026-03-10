#!/usr/bin/env python3
import math
import os
import sys
import time
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
BINDINGS_DIR = ROOT / "bindings" / "generated"
sys.path.insert(0, str(BINDINGS_DIR))

# genny currently emits fig_draw.py expecting libfig_draw.*, while config.nims
# outputs libfigdraw.*. Create a local symlink/copy fallback before import.
if sys.platform == "darwin":
    expected = BINDINGS_DIR / "libfig_draw.dylib"
    actual = BINDINGS_DIR / "libfigdraw.dylib"
    if (not expected.exists()) and actual.exists():
        try:
            expected.symlink_to(actual.name)
        except OSError:
            expected.write_bytes(actual.read_bytes())
elif sys.platform.startswith("linux"):
    expected = BINDINGS_DIR / "libfig_draw.so"
    actual = BINDINGS_DIR / "libfigdraw.so"
    if (not expected.exists()) and actual.exists():
        try:
            expected.symlink_to(actual.name)
        except OSError:
            expected.write_bytes(actual.read_bytes())
elif sys.platform == "win32":
    expected = BINDINGS_DIR / "fig_draw.dll"
    actual = BINDINGS_DIR / "figdraw.dll"
    if (not expected.exists()) and actual.exists():
        expected.write_bytes(actual.read_bytes())

import fig_draw as fd


COPIES = 100
RUN_ONCE = os.getenv("FIGDRAW_RUN_ONCE", "").strip().lower() in {"1", "true", "yes"}
NO_SLEEP = os.getenv("FIGDRAW_NO_SLEEP", "1").strip().lower() in {"1", "true", "yes"}


def make_render_tree(width: float, height: float, frame: int) -> fd.Renders:
    renders = fd.Renders()
    t = frame * 0.02

    background = fd.new_rectangle_fig(0.0, 0.0, width, height)
    background.set_fill_color(255, 255, 255, 155)
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

    for i in range(COPIES):
        seed_x = math.sin(i * 78.233) * 43758.5453
        seed_y = math.sin((i + 19) * 37.719) * 24634.6345
        base_x = (seed_x - math.floor(seed_x)) * max_x if max_x > 0 else 0.0
        base_y = (seed_y - math.floor(seed_y)) * max_y if max_y > 0 else 0.0

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

        red_fig = fd.new_rectangle_fig(red_start_x + offset_x, red_start_y + offset_y, red_w, red_h)
        red_fig.set_fill_color(220, 40, 40, 155)
        corner_pulse = 0.5 + 0.5 * math.sin(t * 1.25 + i * 0.11)
        c0 = 4.0 + 26.0 * corner_pulse
        c1 = 6.0 + 22.0 * (1.0 - corner_pulse)
        c2 = 8.0 + 18.0 * (0.5 + 0.5 * math.sin(t * 0.7 + i * 0.05))
        c3 = 10.0 + 16.0 * (0.5 + 0.5 * math.cos(t * 0.8 + i * 0.06))
        red_fig.set_corners(c0, c1, c2, c3)
        red_fig.set_stroke(5.0, 0, 0, 0, 155)
        renders.add_root(0, red_fig)

        green_fig = fd.new_rectangle_fig(
            green_start_x + offset_x, green_start_y + offset_y, green_w, green_h
        )
        green_fig.set_fill_color(40, 180, 90, 155)
        green_corner_pulse = 0.5 + 0.5 * math.cos(t * 0.95 + i * 0.08)
        g0 = 6.0 + 22.0 * green_corner_pulse
        g1 = 8.0 + 18.0 * (1.0 - green_corner_pulse)
        g2 = 10.0 + 16.0 * (0.5 + 0.5 * math.cos(t * 0.75 + i * 0.04))
        g3 = 12.0 + 14.0 * (0.5 + 0.5 * math.sin(t * 0.85 + i * 0.05))
        green_fig.set_corners(g0, g1, g2, g3)
        renders.add_root(0, green_fig)

        blue_fig = fd.new_rectangle_fig(blue_start_x + offset_x, blue_start_y + offset_y, blue_w, blue_h)
        blue_fig.set_fill_color(60, 90, 220, 155)
        blue_fig.set_stroke(4.0, 255, 255, 255, 210)
        renders.add_root(0, blue_fig)

    return renders


def main() -> int:
    fd.set_fig_data_dir(str(ROOT / "data"))

    typeface = fd.load_typeface_binding("Ubuntu.ttf")
    if not typeface:
        print("Failed to load typeface: Ubuntu.ttf")
        return 1
    fps_font = fd.FigFontRef(typeface, 18.0)
    fps_text = "0.0 FPS"

    renderer = fd.new_siwin_renderer_binding(512, 1.0)
    if not renderer:
        print("Failed to create Siwin renderer")
        return 1

    title = "Siwin RenderList (Python)"
    window = fd.new_siwin_window_binding(800, 600, False, title, True, 0, True, False, False)
    if not window:
        print("Failed to create Siwin window")
        return 1

    auto_scale = window.configure_ui_scale_binding("")
    renderer.setup_backend_binding(window)
    window.first_step_window_binding(True)
    window.make_current_window_binding()
    print("Backend initialized")

    frames = 0
    fps_frames = 0
    frame = 0
    fps_start = time.time()
    make_render_tree_ms_sum = 0.0
    render_frame_ms_sum = 0.0
    last_element_count = 0

    try:
        while window.window_is_open_binding():
            window.refresh_ui_scale_binding(auto_scale)

            frame += 1
            frames += 1
            fps_frames += 1

            renderer.begin_frame_binding()
            width = window.logical_width_binding()
            height = window.logical_height_binding()

            t0 = time.perf_counter()
            renders = make_render_tree(width, height, frame)
            make_render_tree_ms_sum += (time.perf_counter() - t0) * 1000.0
            last_element_count = renders.layer_node_count(0)

            hud_margin = 12.0
            hud_w = 180.0
            hud_h = 34.0
            hud_x = width - hud_w - hud_margin
            hud_y = hud_margin
            hud_rect = fd.new_rectangle_fig(hud_x, hud_y, hud_w, hud_h)
            hud_rect.set_fill_color(0, 0, 0, 155)
            hud_rect.set_corners(8.0, 8.0, 8.0, 8.0)
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
                h_align=2,  # Right
                v_align=1,  # Middle
                min_content=False,
                wrap=False,
            )
            if fps_layout:
                hud_text = fd.new_text_fig(hud_text_x, hud_text_y, hud_text_w, hud_text_h)
                hud_text.set_fill_color(0, 0, 0, 0)
                fd.set_fig_text_layout_binding(hud_text, fps_layout)
                renders.add_root(0, hud_text)

            t1 = time.perf_counter()
            renderer.render_frame_binding(renders, width, height)
            render_frame_ms_sum += (time.perf_counter() - t1) * 1000.0
            renderer.end_frame_binding()
            window.present_now_binding()

            window.redraw_window_binding()
            window.step_window_binding()

            now = time.time()
            elapsed = now - fps_start
            if elapsed >= 1.0:
                fps = fps_frames / elapsed
                fps_text = f"{fps:0.1f} FPS"
                avg_make = make_render_tree_ms_sum / max(1, fps_frames)
                avg_render = render_frame_ms_sum / max(1, fps_frames)
                print(
                    "fps:",
                    f"{fps:.1f}",
                    "| elems:",
                    last_element_count,
                    "| makeRenderTree avg(ms):",
                    f"{avg_make:.3f}",
                    "| renderFrame avg(ms):",
                    f"{avg_render:.3f}",
                )
                fps_frames = 0
                fps_start = now
                make_render_tree_ms_sum = 0.0
                render_frame_ms_sum = 0.0

            if RUN_ONCE and frames >= 1:
                break
            if (not NO_SLEEP) and window.window_is_open_binding():
                time.sleep(0.016)
    finally:
        window.close_window_binding()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
