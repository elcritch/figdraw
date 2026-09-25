## Use the X11 types paired with Siwin's GLX API on each supported version.
import x11/x as x11Types except Window
import x11/[xlib, xutil]
import siwin/platforms/x11/glx as siX11Glx

when compiles(
  siX11Glx.newGlxContext(cast[xlib.PDisplay](nil), cast[xutil.PXVisualInfo](nil))
):
  import x11/xlib as x11Api
  import x11/xutil as x11VisualApi

  proc x11XcbConnection*(
    display: pointer
  ): pointer {.cdecl, dynlib: "libX11-xcb.so.1", importc: "XGetXCBConnection".}

else:
  import siwin/platforms/x11/x11api as x11Api
  import siwin/platforms/x11/x11api as x11VisualApi

  proc x11XcbConnection*(display: pointer): pointer =
    if x11Api.x11XcbAvailable():
      x11Api.XGetXCBConnection(cast[x11Api.PDisplay](display))

type SiwinGlxDisplay* = x11Api.PDisplay
type SiwinGlxVisualInfo = x11VisualApi.PXVisualInfo

proc getX11VisualInfo*(
    display: SiwinGlxDisplay, drawable: x11Types.Drawable
): SiwinGlxVisualInfo =
  var attributes: x11Api.XWindowAttributes
  if x11Api.XGetWindowAttributes(display, drawable, attributes.addr) == 0:
    raise newException(ValueError, "Failed to query X11 window visual")

  var
    visual =
      x11VisualApi.XVisualInfo(visualid: x11Api.XVisualIDFromVisual(attributes.visual))
    count: cint
  result = x11VisualApi.XGetVisualInfo(
    display, x11VisualApi.VisualIDMask.clong, visual.addr, count.addr
  )
  if result == nil or count <= 0:
    if result != nil:
      discard x11Api.XFree(result)
    raise newException(ValueError, "Failed to resolve X11 visual for OpenGL")

proc freeX11VisualInfo*(visual: SiwinGlxVisualInfo) =
  discard x11Api.XFree(visual)
