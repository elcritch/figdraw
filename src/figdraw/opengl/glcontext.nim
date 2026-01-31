when defined(macosx) and defined(feature.figdraw.metal):
  import ./glcontext_metal as impl
else:
  import ./glcontext_gl as impl

export impl
