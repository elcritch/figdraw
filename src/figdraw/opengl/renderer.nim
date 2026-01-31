when defined(macosx) and defined(feature.figdraw.metal):
  import ./renderer_metal as impl
else:
  import ./renderer_gl as impl

export impl
