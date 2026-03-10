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

