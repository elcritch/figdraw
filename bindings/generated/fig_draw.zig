const std = @import("std");

extern fn fig_draw_fig_data_dir() callconv(.C) [*:0]const u8;
pub inline fn figDataDir() [:0]const u8 {
    return std.mem.span(fig_draw_fig_data_dir());
}

extern fn fig_draw_set_fig_data_dir(dir: [*:0]const u8) callconv(.C) void;
pub inline fn setFigDataDir(dir: [:0]const u8) void {
    return fig_draw_set_fig_data_dir(dir.ptr);
}

extern fn fig_draw_fig_ui_scale() callconv(.C) f32;
pub inline fn figUiScale() f32 {
    return fig_draw_fig_ui_scale();
}

extern fn fig_draw_set_fig_ui_scale(scale: f32) callconv(.C) void;
pub inline fn setFigUiScale(scale: f32) void {
    return fig_draw_set_fig_ui_scale(scale);
}

extern fn fig_draw_scaled(a: f32) callconv(.C) f32;
pub inline fn scaled(a: f32) f32 {
    return fig_draw_scaled(a);
}

extern fn fig_draw_descaled(a: f32) callconv(.C) f32;
pub inline fn descaled(a: f32) f32 {
    return fig_draw_descaled(a);
}

