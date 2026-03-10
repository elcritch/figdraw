const std = @import("std");

pub const FigKind = enum(u8) {
    fig_kind = 0,
};

pub const Fig = opaque {
    extern fn fig_draw_fig_unref(self: *Fig) callconv(.C) void;
    pub inline fn deinit(self: *Fig) void {
        return fig_draw_fig_unref(self);
    }

    extern fn fig_draw_new_fig() callconv(.C) *Fig;
    pub inline fn init() *Fig {
        return fig_draw_new_fig();
    }

    extern fn fig_draw_fig_copy(self: *Fig) callconv(.C) *Fig;
    pub inline fn copy(self: *Fig) *Fig {
        return fig_draw_fig_copy(self);
    }

    extern fn fig_draw_fig_kind(self: *Fig) callconv(.C) FigKind;
    pub inline fn kind(self: *Fig) FigKind {
        return fig_draw_fig_kind(self);
    }

    extern fn fig_draw_fig_set_kind(self: *Fig, kind: FigKind) callconv(.C) void;
    pub inline fn setKind(self: *Fig, kind: FigKind) void {
        return fig_draw_fig_set_kind(self, kind);
    }

    extern fn fig_draw_fig_z_level(self: *Fig) callconv(.C) ZLevel;
    pub inline fn zLevel(self: *Fig) ZLevel {
        return fig_draw_fig_z_level(self);
    }

    extern fn fig_draw_fig_set_zlevel(self: *Fig, z_level: ZLevel) callconv(.C) void;
    pub inline fn setZLevel(self: *Fig, z_level: ZLevel) void {
        return fig_draw_fig_set_zlevel(self, z_level);
    }

    extern fn fig_draw_fig_x(self: *Fig) callconv(.C) f32;
    pub inline fn x(self: *Fig) f32 {
        return fig_draw_fig_x(self);
    }

    extern fn fig_draw_fig_y(self: *Fig) callconv(.C) f32;
    pub inline fn y(self: *Fig) f32 {
        return fig_draw_fig_y(self);
    }

    extern fn fig_draw_fig_width(self: *Fig) callconv(.C) f32;
    pub inline fn width(self: *Fig) f32 {
        return fig_draw_fig_width(self);
    }

    extern fn fig_draw_fig_height(self: *Fig) callconv(.C) f32;
    pub inline fn height(self: *Fig) f32 {
        return fig_draw_fig_height(self);
    }

    extern fn fig_draw_fig_set_screen_box(self: *Fig, x: f32, y: f32, w: f32, h: f32) callconv(.C) void;
    pub inline fn setScreenBox(self: *Fig, x: f32, y: f32, w: f32, h: f32) void {
        return fig_draw_fig_set_screen_box(self, x, y, w, h);
    }

    extern fn fig_draw_fig_set_fill_color(self: *Fig, r: u8, g: u8, b: u8, a: u8) callconv(.C) void;
    pub inline fn setFillColor(self: *Fig, r: u8, g: u8, b: u8, a: u8) void {
        return fig_draw_fig_set_fill_color(self, r, g, b, a);
    }

    extern fn fig_draw_fig_set_rotation(self: *Fig, rotation: f32) callconv(.C) void;
    pub inline fn setRotation(self: *Fig, rotation: f32) void {
        return fig_draw_fig_set_rotation(self, rotation);
    }
};

pub const RenderList = opaque {
    extern fn fig_draw_render_list_unref(self: *RenderList) callconv(.C) void;
    pub inline fn deinit(self: *RenderList) void {
        return fig_draw_render_list_unref(self);
    }

    extern fn fig_draw_new_render_list() callconv(.C) *RenderList;
    pub inline fn init() *RenderList {
        return fig_draw_new_render_list();
    }

    extern fn fig_draw_render_list_copy(self: *RenderList) callconv(.C) *RenderList;
    pub inline fn copy(self: *RenderList) *RenderList {
        return fig_draw_render_list_copy(self);
    }

    extern fn fig_draw_render_list_clear(self: *RenderList) callconv(.C) void;
    pub inline fn clear(self: *RenderList) void {
        return fig_draw_render_list_clear(self);
    }

    extern fn fig_draw_render_list_node_count(self: *RenderList) callconv(.C) isize;
    pub inline fn nodeCount(self: *RenderList) isize {
        return fig_draw_render_list_node_count(self);
    }

    extern fn fig_draw_render_list_root_count(self: *RenderList) callconv(.C) isize;
    pub inline fn rootCount(self: *RenderList) isize {
        return fig_draw_render_list_root_count(self);
    }

    extern fn fig_draw_render_list_add_root(self: *RenderList, root: *Fig) callconv(.C) i16;
    pub inline fn addRoot(self: *RenderList, root: *Fig) i16 {
        return fig_draw_render_list_add_root(self, root);
    }

    extern fn fig_draw_render_list_add_child(self: *RenderList, parent_idx: i16, child: *Fig) callconv(.C) i16;
    pub inline fn addChild(self: *RenderList, parent_idx: i16, child: *Fig) i16 {
        return fig_draw_render_list_add_child(self, parent_idx, child);
    }

    extern fn fig_draw_render_list_get_node(self: *RenderList, node_idx: i16) callconv(.C) *Fig;
    pub inline fn getNode(self: *RenderList, node_idx: i16) *Fig {
        return fig_draw_render_list_get_node(self, node_idx);
    }

    extern fn fig_draw_render_list_get_root_id(self: *RenderList, root_idx: i16) callconv(.C) i16;
    pub inline fn getRootId(self: *RenderList, root_idx: i16) i16 {
        return fig_draw_render_list_get_root_id(self, root_idx);
    }
};

pub const Renders = opaque {
    extern fn fig_draw_renders_unref(self: *Renders) callconv(.C) void;
    pub inline fn deinit(self: *Renders) void {
        return fig_draw_renders_unref(self);
    }

    extern fn fig_draw_new_renders() callconv(.C) *Renders;
    pub inline fn init() *Renders {
        return fig_draw_new_renders();
    }

    extern fn fig_draw_renders_clear(self: *Renders) callconv(.C) void;
    pub inline fn clear(self: *Renders) void {
        return fig_draw_renders_clear(self);
    }

    extern fn fig_draw_renders_contains_layer(self: *Renders, z_level: ZLevel) callconv(.C) bool;
    pub inline fn containsLayer(self: *Renders, z_level: ZLevel) bool {
        return fig_draw_renders_contains_layer(self, z_level);
    }

    extern fn fig_draw_renders_add_root(self: *Renders, z_level: ZLevel, root: *Fig) callconv(.C) i16;
    pub inline fn addRoot(self: *Renders, z_level: ZLevel, root: *Fig) i16 {
        return fig_draw_renders_add_root(self, z_level, root);
    }

    extern fn fig_draw_renders_add_child(self: *Renders, z_level: ZLevel, parent_idx: i16, child: *Fig) callconv(.C) i16;
    pub inline fn addChild(self: *Renders, z_level: ZLevel, parent_idx: i16, child: *Fig) i16 {
        return fig_draw_renders_add_child(self, z_level, parent_idx, child);
    }

    extern fn fig_draw_renders_layer_node_count(self: *Renders, z_level: ZLevel) callconv(.C) isize;
    pub inline fn layerNodeCount(self: *Renders, z_level: ZLevel) isize {
        return fig_draw_renders_layer_node_count(self, z_level);
    }

    extern fn fig_draw_renders_layer_root_count(self: *Renders, z_level: ZLevel) callconv(.C) isize;
    pub inline fn layerRootCount(self: *Renders, z_level: ZLevel) isize {
        return fig_draw_renders_layer_root_count(self, z_level);
    }

    extern fn fig_draw_renders_get_layer_node(self: *Renders, z_level: ZLevel, node_idx: i16) callconv(.C) *Fig;
    pub inline fn getLayerNode(self: *Renders, z_level: ZLevel, node_idx: i16) *Fig {
        return fig_draw_renders_get_layer_node(self, z_level, node_idx);
    }
};

extern fn fig_draw_new_rectangle_fig(x: f32, y: f32, w: f32, h: f32) callconv(.C) *Fig;
pub inline fn newRectangleFig(x: f32, y: f32, w: f32, h: f32) *Fig {
    return fig_draw_new_rectangle_fig(x, y, w, h);
}

extern fn fig_draw_new_text_fig(x: f32, y: f32, w: f32, h: f32) callconv(.C) *Fig;
pub inline fn newTextFig(x: f32, y: f32, w: f32, h: f32) *Fig {
    return fig_draw_new_text_fig(x, y, w, h);
}

extern fn fig_draw_new_image_fig(x: f32, y: f32, w: f32, h: f32, image_id: i63) callconv(.C) *Fig;
pub inline fn newImageFig(x: f32, y: f32, w: f32, h: f32, image_id: i63) *Fig {
    return fig_draw_new_image_fig(x, y, w, h, image_id);
}

extern fn fig_draw_new_transform_fig(x: f32, y: f32, w: f32, h: f32, tx: f32, ty: f32) callconv(.C) *Fig;
pub inline fn newTransformFig(x: f32, y: f32, w: f32, h: f32, tx: f32, ty: f32) *Fig {
    return fig_draw_new_transform_fig(x, y, w, h, tx, ty);
}

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

extern fn fig_draw_siwin_backend_name_binding() callconv(.C) [*:0]const u8;
pub inline fn siwinBackendNameBinding() [:0]const u8 {
    return std.mem.span(fig_draw_siwin_backend_name_binding());
}

extern fn fig_draw_siwin_window_title_binding(suffix: [*:0]const u8) callconv(.C) [*:0]const u8;
pub inline fn siwinWindowTitleBinding(suffix: [:0]const u8) [:0]const u8 {
    return std.mem.span(fig_draw_siwin_window_title_binding(suffix.ptr));
}

