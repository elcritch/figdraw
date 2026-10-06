## Use Siwin's optional X11 entry points and the types paired with its GLX API.
import siwin/platforms/x11/x11api as x11Api

type
  SiwinGlxDisplay* = x11Api.PDisplay
  # x11api does not re-export Drawable; derive its XID type from the API.
  SiwinGlxDrawable* = typeof(x11Api.XRootWindow(nil, 0))
  SiwinGlxVisualInfo = x11Api.PXVisualInfo

proc x11XcbConnection*(display: pointer): pointer =
  if x11Api.x11XcbAvailable():
    result = x11Api.XGetXCBConnection(cast[x11Api.PDisplay](display))

proc getX11VisualInfo*(
    display: SiwinGlxDisplay, drawable: SiwinGlxDrawable
): SiwinGlxVisualInfo =
  var attributes: x11Api.XWindowAttributes
  if x11Api.XGetWindowAttributes(display, drawable, attributes.addr) == 0:
    raise newException(ValueError, "Failed to query X11 window visual")

  var
    visual = x11Api.XVisualInfo(visualid: x11Api.XVisualIDFromVisual(attributes.visual))
    count: cint
  result =
    x11Api.XGetVisualInfo(display, x11Api.VisualIDMask.clong, visual.addr, count.addr)
  if result == nil or count <= 0:
    if result != nil:
      discard x11Api.XFree(result)
    raise newException(ValueError, "Failed to resolve X11 visual for OpenGL")

proc freeX11VisualInfo*(visual: SiwinGlxVisualInfo) =
  discard x11Api.XFree(visual)
