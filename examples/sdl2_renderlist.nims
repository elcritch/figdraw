
when defined(macosx):
  #const sdlPrefix = "-L" & gorgeEx("brew --prefix sdl2").output & "/lib"
  #switch("passl", sdlPrefix)
  switch("passl", "-Wl,-rpath,/opt/homebrew/opt/sdl2/lib/")
