when defined(useNativeDynlib):
  import figdraw/dynlib as nativeFacade
  export nativeFacade

else:
  import chroma, bumpy, vmath
  from pkg/pixie import Image, newImage, opaqueBounds, `[]`, `[]=`, fill
  import figdraw/commons
  import figdraw/common/fontglyphs
  import figdraw/common/typefaceinfos
  import figdraw/common/typefaces
  import figdraw/fignodes
  import figdraw/renderfragments
  import figdraw/figrender as figrenderer
  import figdraw/utils/drawutils

  export chroma
  export bumpy
  export vmath
  export Image, newImage, opaqueBounds, `[]`, `[]=`, fill

  export commons
  export fontglyphs
  export typefaceinfos
  export typefaces
  export fignodes
  export renderfragments
  export figrenderer
  export drawutils

  when defined(features.figdraw.siwin):
    import figdraw/windowing/siwinshim
    export siwinshim
  when defined(features.figdraw.windy):
    import figdraw/windowing/windyshim
    export windyshim
