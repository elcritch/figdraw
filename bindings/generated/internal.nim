when not defined(gcArc) and not defined(gcOrc):
  {.error: "Please use --gc:arc or --gc:orc when using Genny.".}

when (NimMajor, NimMinor, NimPatch) == (1, 6, 2):
  {.error: "Nim 1.6.2 not supported with Genny due to FFI issues.".}
proc fig_draw_fig_data_dir*(): cstring {.raises: [], cdecl, exportc, dynlib.} =
  figDataDir().cstring

proc fig_draw_set_fig_data_dir*(dir: cstring) {.raises: [], cdecl, exportc, dynlib.} =
  setFigDataDir(dir.`$`)

proc fig_draw_fig_ui_scale*(): float32 {.raises: [], cdecl, exportc, dynlib.} =
  figUiScale()

proc fig_draw_set_fig_ui_scale*(scale: float32) {.raises: [], cdecl, exportc, dynlib.} =
  setFigUiScale(scale)

proc fig_draw_scaled*(a: float32): float32 {.raises: [], cdecl, exportc, dynlib.} =
  scaled(a)

proc fig_draw_descaled*(a: float32): float32 {.raises: [], cdecl, exportc, dynlib.} =
  descaled(a)

