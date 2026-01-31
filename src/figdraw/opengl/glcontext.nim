import ../commons

when UseMetalBackend:
  import ./glcontext_metal as impl
else:
  import ./glcontext_gl as impl

export impl
