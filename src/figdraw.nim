when defined(useNativeDynlib):
  import figdraw/dynlib as nativeFacade

  export nativeFacade
else:
  import chroma
  from pkg/pixie import Image, newImage, opaqueBounds, `[]`, `[]=`, fill
  import figdraw/commons
  import figdraw/common/fontglyphs
  import figdraw/common/typefaceinfos
  import figdraw/common/typefaces
  import figdraw/fignodes
  import figdraw/renderfragments
  import figdraw/figrender as figrenderer

  export
    chroma, commons, fontglyphs, typefaceinfos, typefaces, fignodes, renderfragments,
    figrenderer
  export Image, newImage, opaqueBounds, `[]`, `[]=`, fill
