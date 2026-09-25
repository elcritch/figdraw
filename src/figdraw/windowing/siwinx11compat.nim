## Use the X11 types paired with Siwin's GLX API on each supported version.
import x11/x as x11Types except Window
import x11/[xlib, xutil]
import siwin/platforms/x11/glx as siX11Glx

when compiles(
  siX11Glx.newGlxContext(cast[xlib.PDisplay](nil), cast[xutil.PXVisualInfo](nil))
):
  type SiwinGlxDisplay* = xlib.PDisplay
  type SiwinGlxVisualInfo = xutil.PXVisualInfo

  proc getX11VisualInfo*(
      display: SiwinGlxDisplay, drawable: x11Types.Drawable
  ): SiwinGlxVisualInfo =
    var attributes: xlib.XWindowAttributes
    if xlib.XGetWindowAttributes(display, drawable, attributes.addr) == 0:
      raise newException(ValueError, "Failed to query X11 window visual")

    var
      visual = xutil.XVisualInfo(visualid: xlib.XVisualIDFromVisual(attributes.visual))
      count: cint
    result =
      xutil.XGetVisualInfo(display, xutil.VisualIDMask.clong, visual.addr, count.addr)
    if result == nil or count <= 0:
      if result != nil:
        discard xlib.XFree(result)
      raise newException(ValueError, "Failed to resolve X11 visual for OpenGL")

  proc freeX11VisualInfo*(visual: SiwinGlxVisualInfo) =
    discard xlib.XFree(visual)

else:
  import siwin/platforms/x11/x11api as siX11Api

  type SiwinGlxDisplay* = siX11Api.PDisplay
  type SiwinGlxVisualInfo = siX11Api.PXVisualInfo

  proc getX11VisualInfo*(
      display: SiwinGlxDisplay, drawable: x11Types.Drawable
  ): SiwinGlxVisualInfo =
    var attributes: siX11Api.XWindowAttributes
    if siX11Api.XGetWindowAttributes(display, drawable, attributes.addr) == 0:
      raise newException(ValueError, "Failed to query X11 window visual")

    var
      visual =
        siX11Api.XVisualInfo(visualid: siX11Api.XVisualIDFromVisual(attributes.visual))
      count: cint
    result = siX11Api.XGetVisualInfo(
      display, siX11Api.VisualIDMask.clong, visual.addr, count.addr
    )
    if result == nil or count <= 0:
      if result != nil:
        discard siX11Api.XFree(result)
      raise newException(ValueError, "Failed to resolve X11 visual for OpenGL")

  proc freeX11VisualInfo*(visual: SiwinGlxVisualInfo) =
    discard siX11Api.XFree(visual)
