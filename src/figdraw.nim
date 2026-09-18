when defined(useNativeDynlib):
  import figdraw/dynlib as nativeFacade
  export nativeFacade

  proc readPixieImage*(filePath: string): nativeFacade.Image {.inline.} =
    nativeFacade.readImage(filePath)

else:
  import chroma, bumpy, vmath
  import pkg/pixie as pixie
  from pkg/pixie import
    Image, newImage, opaqueBounds, `[]`, `[]=`, fill, copy, decodeImage, writeFile
  from pkg/pixie/fileformats/png import encodePng
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
  export
    Image, newImage, opaqueBounds, `[]`, `[]=`, fill, copy, decodeImage, writeFile,
    encodePng

  proc readPixieImage*(filePath: string): Image {.inline.} =
    pixie.readImage(filePath)

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
    export siwinshim except
      Window, MouseButton, Key, KeyModifier, MouseEvent, ScrollEventPhase, ScrollEvent,
      KeyEvent
  when defined(features.figdraw.windy):
    import figdraw/windowing/windyshim
    export windyshim
