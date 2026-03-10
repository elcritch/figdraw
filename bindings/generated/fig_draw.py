from ctypes import *
import os, sys

dir = os.path.dirname(sys.modules["fig_draw"].__file__)
if sys.platform == "win32":
  libName = "fig_draw.dll"
elif sys.platform == "darwin":
  libName = "libfig_draw.dylib"
else:
  libName = "libfig_draw.so"
dll = cdll.LoadLibrary(os.path.join(dir, libName))

class FigDrawError(Exception):
    pass

class SeqIterator(object):
    def __init__(self, seq):
        self.idx = 0
        self.seq = seq
    def __iter__(self):
        return self
    def __next__(self):
        if self.idx < len(self.seq):
            self.idx += 1
            return self.seq[self.idx - 1]
        else:
            self.idx = 0
            raise StopIteration

FigKind = c_byte
FIG_KIND = 0

class Fig(Structure):
    _fields_ = [("ref", c_ulonglong)]

    def __bool__(self):
        return self.ref != None

    def __eq__(self, obj):
        return self.ref == obj.ref

    def __del__(self):
        dll.fig_draw_fig_unref(self)

    def __init__(self):
        result = dll.fig_draw_new_fig()
        self.ref = result

    def copy(self):
        result = dll.fig_draw_fig_copy(self)
        return result

    def kind(self):
        result = dll.fig_draw_fig_kind(self)
        return result

    def set_kind(self, kind):
        dll.fig_draw_fig_set_kind(self, kind)

    def z_level(self):
        result = dll.fig_draw_fig_z_level(self)
        return result

    def set_zlevel(self, z_level):
        dll.fig_draw_fig_set_zlevel(self, z_level)

    def x(self):
        result = dll.fig_draw_fig_x(self)
        return result

    def y(self):
        result = dll.fig_draw_fig_y(self)
        return result

    def width(self):
        result = dll.fig_draw_fig_width(self)
        return result

    def height(self):
        result = dll.fig_draw_fig_height(self)
        return result

    def set_screen_box(self, x, y, w, h):
        dll.fig_draw_fig_set_screen_box(self, x, y, w, h)

    def set_fill_color(self, r, g, b, a):
        dll.fig_draw_fig_set_fill_color(self, r, g, b, a)

    def set_rotation(self, rotation):
        dll.fig_draw_fig_set_rotation(self, rotation)

class RenderList(Structure):
    _fields_ = [("ref", c_ulonglong)]

    def __bool__(self):
        return self.ref != None

    def __eq__(self, obj):
        return self.ref == obj.ref

    def __del__(self):
        dll.fig_draw_render_list_unref(self)

    def __init__(self):
        result = dll.fig_draw_new_render_list()
        self.ref = result

    def copy(self):
        result = dll.fig_draw_render_list_copy(self)
        return result

    def clear(self):
        dll.fig_draw_render_list_clear(self)

    def node_count(self):
        result = dll.fig_draw_render_list_node_count(self)
        return result

    def root_count(self):
        result = dll.fig_draw_render_list_root_count(self)
        return result

    def add_root(self, root):
        result = dll.fig_draw_render_list_add_root(self, root)
        return result

    def add_child(self, parent_idx, child):
        result = dll.fig_draw_render_list_add_child(self, parent_idx, child)
        return result

    def get_node(self, node_idx):
        result = dll.fig_draw_render_list_get_node(self, node_idx)
        return result

    def get_root_id(self, root_idx):
        result = dll.fig_draw_render_list_get_root_id(self, root_idx)
        return result

class Renders(Structure):
    _fields_ = [("ref", c_ulonglong)]

    def __bool__(self):
        return self.ref != None

    def __eq__(self, obj):
        return self.ref == obj.ref

    def __del__(self):
        dll.fig_draw_renders_unref(self)

    def __init__(self):
        result = dll.fig_draw_new_renders()
        self.ref = result

    def clear(self):
        dll.fig_draw_renders_clear(self)

    def contains_layer(self, z_level):
        result = dll.fig_draw_renders_contains_layer(self, z_level)
        return result

    def add_root(self, z_level, root):
        result = dll.fig_draw_renders_add_root(self, z_level, root)
        return result

    def add_child(self, z_level, parent_idx, child):
        result = dll.fig_draw_renders_add_child(self, z_level, parent_idx, child)
        return result

    def layer_node_count(self, z_level):
        result = dll.fig_draw_renders_layer_node_count(self, z_level)
        return result

    def layer_root_count(self, z_level):
        result = dll.fig_draw_renders_layer_root_count(self, z_level)
        return result

    def get_layer_node(self, z_level, node_idx):
        result = dll.fig_draw_renders_get_layer_node(self, z_level, node_idx)
        return result

def new_rectangle_fig(x, y, w, h):
    result = dll.fig_draw_new_rectangle_fig(x, y, w, h)
    return result

def new_text_fig(x, y, w, h):
    result = dll.fig_draw_new_text_fig(x, y, w, h)
    return result

def new_image_fig(x, y, w, h, image_id):
    result = dll.fig_draw_new_image_fig(x, y, w, h, image_id)
    return result

def new_transform_fig(x, y, w, h, tx, ty):
    result = dll.fig_draw_new_transform_fig(x, y, w, h, tx, ty)
    return result

def fig_data_dir():
    result = dll.fig_draw_fig_data_dir().decode("utf8")
    return result

def set_fig_data_dir(dir):
    dll.fig_draw_set_fig_data_dir(dir.encode("utf8"))

def fig_ui_scale():
    result = dll.fig_draw_fig_ui_scale()
    return result

def set_fig_ui_scale(scale):
    dll.fig_draw_set_fig_ui_scale(scale)

def scaled(a):
    result = dll.fig_draw_scaled(a)
    return result

def descaled(a):
    result = dll.fig_draw_descaled(a)
    return result

class SiwinWindowRef(Structure):
    _fields_ = [("ref", c_ulonglong)]

    def __bool__(self):
        return self.ref != None

    def __eq__(self, obj):
        return self.ref == obj.ref

    def __del__(self):
        dll.fig_draw_siwin_window_ref_unref(self)

    def close_window_binding(self):
        dll.fig_draw_siwin_window_ref_close_window_binding(self)

    def step_window_binding(self):
        dll.fig_draw_siwin_window_ref_step_window_binding(self)

    def make_current_window_binding(self):
        dll.fig_draw_siwin_window_ref_make_current_window_binding(self)

    def window_is_open_binding(self):
        result = dll.fig_draw_siwin_window_ref_window_is_open_binding(self)
        return result

    def siwin_display_server_name_binding(self):
        result = dll.fig_draw_siwin_window_ref_siwin_display_server_name_binding(self).decode("utf8")
        return result

    def backing_width_binding(self):
        result = dll.fig_draw_siwin_window_ref_backing_width_binding(self)
        return result

    def backing_height_binding(self):
        result = dll.fig_draw_siwin_window_ref_backing_height_binding(self)
        return result

    def logical_width_binding(self):
        result = dll.fig_draw_siwin_window_ref_logical_width_binding(self)
        return result

    def logical_height_binding(self):
        result = dll.fig_draw_siwin_window_ref_logical_height_binding(self)
        return result

    def content_scale_binding(self):
        result = dll.fig_draw_siwin_window_ref_content_scale_binding(self)
        return result

    def configure_ui_scale_binding(self, env_var):
        result = dll.fig_draw_siwin_window_ref_configure_ui_scale_binding(self, env_var.encode("utf8"))
        return result

    def refresh_ui_scale_binding(self, auto_scale):
        dll.fig_draw_siwin_window_ref_refresh_ui_scale_binding(self, auto_scale)

    def present_now_binding(self):
        dll.fig_draw_siwin_window_ref_present_now_binding(self)

class SiwinRendererRef(Structure):
    _fields_ = [("ref", c_ulonglong)]

    def __bool__(self):
        return self.ref != None

    def __eq__(self, obj):
        return self.ref == obj.ref

    def __del__(self):
        dll.fig_draw_siwin_renderer_ref_unref(self)

    def siwin_backend_name_for_renderer_binding(self):
        result = dll.fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding(self).decode("utf8")
        return result

    def siwin_window_title_for_renderer_binding(self, window, suffix):
        result = dll.fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding(self, window, suffix.encode("utf8")).decode("utf8")
        return result

    def setup_backend_binding(self, window):
        dll.fig_draw_siwin_renderer_ref_setup_backend_binding(self, window)

    def begin_frame_binding(self):
        dll.fig_draw_siwin_renderer_ref_begin_frame_binding(self)

    def end_frame_binding(self):
        dll.fig_draw_siwin_renderer_ref_end_frame_binding(self)

class SiwinMetalLayerRef(Structure):
    _fields_ = [("ref", c_ulonglong)]

    def __bool__(self):
        return self.ref != None

    def __eq__(self, obj):
        return self.ref == obj.ref

    def __del__(self):
        dll.fig_draw_siwin_metal_layer_ref_unref(self)

    def update_metal_layer_binding(self, window):
        dll.fig_draw_siwin_metal_layer_ref_update_metal_layer_binding(self, window)

    def set_opaque_binding(self, opaque):
        dll.fig_draw_siwin_metal_layer_ref_set_opaque_binding(self, opaque)

def siwin_backend_name_binding():
    result = dll.fig_draw_siwin_backend_name_binding().decode("utf8")
    return result

def siwin_window_title_binding(suffix):
    result = dll.fig_draw_siwin_window_title_binding(suffix.encode("utf8")).decode("utf8")
    return result

def shared_siwin_globals_ptr_binding():
    result = dll.fig_draw_shared_siwin_globals_ptr_binding()
    return result

def new_siwin_renderer_binding(atlas_size, pixel_scale):
    result = dll.fig_draw_new_siwin_renderer_binding(atlas_size, pixel_scale)
    return result

def new_siwin_window_binding(width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent):
    result = dll.fig_draw_new_siwin_window_binding(width, height, fullscreen, title.encode("utf8"), vsync, msaa, resizable, frameless, transparent)
    return result

def new_siwin_window_for_renderer_binding(renderer, width, height, fullscreen, title, vsync, msaa, resizable, frameless, transparent):
    result = dll.fig_draw_new_siwin_window_for_renderer_binding(renderer, width, height, fullscreen, title.encode("utf8"), vsync, msaa, resizable, frameless, transparent)
    return result

def attach_metal_layer_binding(window, device_ptr):
    result = dll.fig_draw_attach_metal_layer_binding(window, device_ptr)
    return result

dll.fig_draw_fig_unref.argtypes = [Fig]
dll.fig_draw_fig_unref.restype = None

dll.fig_draw_new_fig.argtypes = []
dll.fig_draw_new_fig.restype = c_ulonglong

dll.fig_draw_fig_copy.argtypes = [Fig]
dll.fig_draw_fig_copy.restype = Fig

dll.fig_draw_fig_kind.argtypes = [Fig]
dll.fig_draw_fig_kind.restype = FigKind

dll.fig_draw_fig_set_kind.argtypes = [Fig, FigKind]
dll.fig_draw_fig_set_kind.restype = None

dll.fig_draw_fig_z_level.argtypes = [Fig]
dll.fig_draw_fig_z_level.restype = ZLevel

dll.fig_draw_fig_set_zlevel.argtypes = [Fig, ZLevel]
dll.fig_draw_fig_set_zlevel.restype = None

dll.fig_draw_fig_x.argtypes = [Fig]
dll.fig_draw_fig_x.restype = c_float

dll.fig_draw_fig_y.argtypes = [Fig]
dll.fig_draw_fig_y.restype = c_float

dll.fig_draw_fig_width.argtypes = [Fig]
dll.fig_draw_fig_width.restype = c_float

dll.fig_draw_fig_height.argtypes = [Fig]
dll.fig_draw_fig_height.restype = c_float

dll.fig_draw_fig_set_screen_box.argtypes = [Fig, c_float, c_float, c_float, c_float]
dll.fig_draw_fig_set_screen_box.restype = None

dll.fig_draw_fig_set_fill_color.argtypes = [Fig, c_ubyte, c_ubyte, c_ubyte, c_ubyte]
dll.fig_draw_fig_set_fill_color.restype = None

dll.fig_draw_fig_set_rotation.argtypes = [Fig, c_float]
dll.fig_draw_fig_set_rotation.restype = None

dll.fig_draw_render_list_unref.argtypes = [RenderList]
dll.fig_draw_render_list_unref.restype = None

dll.fig_draw_new_render_list.argtypes = []
dll.fig_draw_new_render_list.restype = c_ulonglong

dll.fig_draw_render_list_copy.argtypes = [RenderList]
dll.fig_draw_render_list_copy.restype = RenderList

dll.fig_draw_render_list_clear.argtypes = [RenderList]
dll.fig_draw_render_list_clear.restype = None

dll.fig_draw_render_list_node_count.argtypes = [RenderList]
dll.fig_draw_render_list_node_count.restype = c_longlong

dll.fig_draw_render_list_root_count.argtypes = [RenderList]
dll.fig_draw_render_list_root_count.restype = c_longlong

dll.fig_draw_render_list_add_root.argtypes = [RenderList, Fig]
dll.fig_draw_render_list_add_root.restype = c_short

dll.fig_draw_render_list_add_child.argtypes = [RenderList, c_short, Fig]
dll.fig_draw_render_list_add_child.restype = c_short

dll.fig_draw_render_list_get_node.argtypes = [RenderList, c_short]
dll.fig_draw_render_list_get_node.restype = Fig

dll.fig_draw_render_list_get_root_id.argtypes = [RenderList, c_short]
dll.fig_draw_render_list_get_root_id.restype = c_short

dll.fig_draw_renders_unref.argtypes = [Renders]
dll.fig_draw_renders_unref.restype = None

dll.fig_draw_new_renders.argtypes = []
dll.fig_draw_new_renders.restype = c_ulonglong

dll.fig_draw_renders_clear.argtypes = [Renders]
dll.fig_draw_renders_clear.restype = None

dll.fig_draw_renders_contains_layer.argtypes = [Renders, ZLevel]
dll.fig_draw_renders_contains_layer.restype = c_bool

dll.fig_draw_renders_add_root.argtypes = [Renders, ZLevel, Fig]
dll.fig_draw_renders_add_root.restype = c_short

dll.fig_draw_renders_add_child.argtypes = [Renders, ZLevel, c_short, Fig]
dll.fig_draw_renders_add_child.restype = c_short

dll.fig_draw_renders_layer_node_count.argtypes = [Renders, ZLevel]
dll.fig_draw_renders_layer_node_count.restype = c_longlong

dll.fig_draw_renders_layer_root_count.argtypes = [Renders, ZLevel]
dll.fig_draw_renders_layer_root_count.restype = c_longlong

dll.fig_draw_renders_get_layer_node.argtypes = [Renders, ZLevel, c_short]
dll.fig_draw_renders_get_layer_node.restype = Fig

dll.fig_draw_new_rectangle_fig.argtypes = [c_float, c_float, c_float, c_float]
dll.fig_draw_new_rectangle_fig.restype = Fig

dll.fig_draw_new_text_fig.argtypes = [c_float, c_float, c_float, c_float]
dll.fig_draw_new_text_fig.restype = Fig

dll.fig_draw_new_image_fig.argtypes = [c_float, c_float, c_float, c_float, c_longlong]
dll.fig_draw_new_image_fig.restype = Fig

dll.fig_draw_new_transform_fig.argtypes = [c_float, c_float, c_float, c_float, c_float, c_float]
dll.fig_draw_new_transform_fig.restype = Fig

dll.fig_draw_fig_data_dir.argtypes = []
dll.fig_draw_fig_data_dir.restype = c_char_p

dll.fig_draw_set_fig_data_dir.argtypes = [c_char_p]
dll.fig_draw_set_fig_data_dir.restype = None

dll.fig_draw_fig_ui_scale.argtypes = []
dll.fig_draw_fig_ui_scale.restype = c_float

dll.fig_draw_set_fig_ui_scale.argtypes = [c_float]
dll.fig_draw_set_fig_ui_scale.restype = None

dll.fig_draw_scaled.argtypes = [c_float]
dll.fig_draw_scaled.restype = c_float

dll.fig_draw_descaled.argtypes = [c_float]
dll.fig_draw_descaled.restype = c_float

dll.fig_draw_siwin_window_ref_unref.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_unref.restype = None

dll.fig_draw_siwin_window_ref_close_window_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_close_window_binding.restype = None

dll.fig_draw_siwin_window_ref_step_window_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_step_window_binding.restype = None

dll.fig_draw_siwin_window_ref_make_current_window_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_make_current_window_binding.restype = None

dll.fig_draw_siwin_window_ref_window_is_open_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_window_is_open_binding.restype = c_bool

dll.fig_draw_siwin_window_ref_siwin_display_server_name_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_siwin_display_server_name_binding.restype = c_char_p

dll.fig_draw_siwin_window_ref_backing_width_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_backing_width_binding.restype = c_int

dll.fig_draw_siwin_window_ref_backing_height_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_backing_height_binding.restype = c_int

dll.fig_draw_siwin_window_ref_logical_width_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_logical_width_binding.restype = c_float

dll.fig_draw_siwin_window_ref_logical_height_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_logical_height_binding.restype = c_float

dll.fig_draw_siwin_window_ref_content_scale_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_content_scale_binding.restype = c_float

dll.fig_draw_siwin_window_ref_configure_ui_scale_binding.argtypes = [SiwinWindowRef, c_char_p]
dll.fig_draw_siwin_window_ref_configure_ui_scale_binding.restype = c_bool

dll.fig_draw_siwin_window_ref_refresh_ui_scale_binding.argtypes = [SiwinWindowRef, c_bool]
dll.fig_draw_siwin_window_ref_refresh_ui_scale_binding.restype = None

dll.fig_draw_siwin_window_ref_present_now_binding.argtypes = [SiwinWindowRef]
dll.fig_draw_siwin_window_ref_present_now_binding.restype = None

dll.fig_draw_siwin_renderer_ref_unref.argtypes = [SiwinRendererRef]
dll.fig_draw_siwin_renderer_ref_unref.restype = None

dll.fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding.argtypes = [SiwinRendererRef]
dll.fig_draw_siwin_renderer_ref_siwin_backend_name_for_renderer_binding.restype = c_char_p

dll.fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding.argtypes = [SiwinRendererRef, SiwinWindowRef, c_char_p]
dll.fig_draw_siwin_renderer_ref_siwin_window_title_for_renderer_binding.restype = c_char_p

dll.fig_draw_siwin_renderer_ref_setup_backend_binding.argtypes = [SiwinRendererRef, SiwinWindowRef]
dll.fig_draw_siwin_renderer_ref_setup_backend_binding.restype = None

dll.fig_draw_siwin_renderer_ref_begin_frame_binding.argtypes = [SiwinRendererRef]
dll.fig_draw_siwin_renderer_ref_begin_frame_binding.restype = None

dll.fig_draw_siwin_renderer_ref_end_frame_binding.argtypes = [SiwinRendererRef]
dll.fig_draw_siwin_renderer_ref_end_frame_binding.restype = None

dll.fig_draw_siwin_metal_layer_ref_unref.argtypes = [SiwinMetalLayerRef]
dll.fig_draw_siwin_metal_layer_ref_unref.restype = None

dll.fig_draw_siwin_metal_layer_ref_update_metal_layer_binding.argtypes = [SiwinMetalLayerRef, SiwinWindowRef]
dll.fig_draw_siwin_metal_layer_ref_update_metal_layer_binding.restype = None

dll.fig_draw_siwin_metal_layer_ref_set_opaque_binding.argtypes = [SiwinMetalLayerRef, c_bool]
dll.fig_draw_siwin_metal_layer_ref_set_opaque_binding.restype = None

dll.fig_draw_siwin_backend_name_binding.argtypes = []
dll.fig_draw_siwin_backend_name_binding.restype = c_char_p

dll.fig_draw_siwin_window_title_binding.argtypes = [c_char_p]
dll.fig_draw_siwin_window_title_binding.restype = c_char_p

dll.fig_draw_shared_siwin_globals_ptr_binding.argtypes = []
dll.fig_draw_shared_siwin_globals_ptr_binding.restype = c_ulonglong

dll.fig_draw_new_siwin_renderer_binding.argtypes = [c_longlong, c_float]
dll.fig_draw_new_siwin_renderer_binding.restype = SiwinRendererRef

dll.fig_draw_new_siwin_window_binding.argtypes = [c_int, c_int, c_bool, c_char_p, c_bool, c_int, c_bool, c_bool, c_bool]
dll.fig_draw_new_siwin_window_binding.restype = SiwinWindowRef

dll.fig_draw_new_siwin_window_for_renderer_binding.argtypes = [SiwinRendererRef, c_int, c_int, c_bool, c_char_p, c_bool, c_int, c_bool, c_bool, c_bool]
dll.fig_draw_new_siwin_window_for_renderer_binding.restype = SiwinWindowRef

dll.fig_draw_attach_metal_layer_binding.argtypes = [SiwinWindowRef, c_ulonglong]
dll.fig_draw_attach_metal_layer_binding.restype = SiwinMetalLayerRef

