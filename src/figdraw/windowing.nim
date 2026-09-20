when defined(useNativeDynlib):
  import figdraw/windowing/dynlib as nativeFacade
  export nativeFacade
else:
  when defined(features.figdraw.siwin):
    import figdraw/windowing/siwinshim
    export siwinshim
  when defined(features.figdraw.windy):
    import figdraw/windowing/windyshim
    export windyshim
