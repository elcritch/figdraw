import bumpy, chroma, unicode, vmath

export bumpy, chroma, unicode, vmath

when defined(windows):
  const libName = "fig_draw.dll"
elif defined(macosx):
  const libName = "libfig_draw.dylib"
else:
  const libName = "libfig_draw.so"

{.push dynlib: libName.}

type FigDrawError = object of ValueError

proc fig_draw_fig_data_dir(): cstring {.importc: "fig_draw_fig_data_dir", cdecl.}

proc figDataDir*(): cstring {.inline.} =
  result = fig_draw_fig_data_dir()

proc fig_draw_set_fig_data_dir(dir: cstring) {.importc: "fig_draw_set_fig_data_dir", cdecl.}

proc setFigDataDir*(dir: string) {.inline.} =
  fig_draw_set_fig_data_dir(dir.cstring)

proc fig_draw_fig_ui_scale(): float32 {.importc: "fig_draw_fig_ui_scale", cdecl.}

proc figUiScale*(): float32 {.inline.} =
  result = fig_draw_fig_ui_scale()

proc fig_draw_set_fig_ui_scale(scale: float32) {.importc: "fig_draw_set_fig_ui_scale", cdecl.}

proc setFigUiScale*(scale: float32) {.inline.} =
  fig_draw_set_fig_ui_scale(scale)

proc fig_draw_scaled(a: float32): float32 {.importc: "fig_draw_scaled", cdecl.}

proc scaled*(a: float32): float32 {.inline.} =
  result = fig_draw_scaled(a)

proc fig_draw_descaled(a: float32): float32 {.importc: "fig_draw_descaled", cdecl.}

proc descaled*(a: float32): float32 {.inline.} =
  result = fig_draw_descaled(a)

