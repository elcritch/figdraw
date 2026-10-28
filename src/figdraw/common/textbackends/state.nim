## Text backend configuration and per-thread selection.

type
  TextBackendKind* {.pure.} = enum
    Pixie
    Harfbuzzy
    Hybrid
    Uirelays

  GlyphRasterBackend* {.pure.} = enum
    Automatic
    Pixie
    Harfbuzz
    Uirelays

const figdrawTextBackend* {.strdefine.} =
  when defined(feature.figdraw.textBackendHarfbuzzy):
    "harfbuzzy"
  elif defined(feature.figdraw.textBackendUirelays):
    "uirelays"
  elif defined(harfbuzzyStatic) or defined(features.harfbuzzy.static):
    "pixie"
  else:
    "runtime"

const runtimeTextBackends* = figdrawTextBackend == "runtime"

static:
  doAssert figdrawTextBackend in ["pixie", "harfbuzzy", "hybrid", "runtime", "uirelays"]

when runtimeTextBackends:
  import std/macros
  import pkg/harfbuzzy as hb
  import pkg/harfbuzzy/raw as hbRaw

  var selectedBackend {.threadvar.}: TextBackendKind
  var backendInitialized {.threadvar.}: bool

  macro allAvailable(symbols: varargs[untyped]): untyped =
    result = newLit(true)
    for symbol in symbols:
      let address = newTree(nnkCast, ident("pointer"), symbol)
      result = infix(result, "and", infix(address, "!=", newNilLit()))

  proc harfbuzzyAvailable*(): bool =
    ## Missing libraries and unsupported versions leave Pixie available.
    try:
      hb.loadHarfbuzz()
      hb.loadFribidi()
      if not allAvailable(
        hbRaw.hb_version_atleast, hbRaw.hb_blob_create, hbRaw.hb_blob_reference,
        hbRaw.hb_blob_destroy, hbRaw.hb_face_create, hbRaw.hb_face_reference,
        hbRaw.hb_face_destroy, hbRaw.hb_face_get_upem, hbRaw.hb_font_create,
        hbRaw.hb_font_reference, hbRaw.hb_font_destroy, hbRaw.hb_font_set_scale,
        hbRaw.hb_font_set_variations, hbRaw.hb_font_get_nominal_glyph,
        hbRaw.hb_font_get_glyph, hbRaw.hb_font_get_glyph_h_advance,
        hbRaw.hb_font_get_glyph_extents, hbRaw.hb_ot_font_set_funcs,
        hbRaw.hb_tag_from_string, hbRaw.hb_tag_to_string, hbRaw.hb_language_from_string,
        hbRaw.hb_language_get_default, hbRaw.hb_unicode_funcs_get_default,
        hbRaw.hb_unicode_script, hbRaw.hb_script_to_iso15924_tag,
        hbRaw.hb_buffer_create, hbRaw.hb_buffer_reference, hbRaw.hb_buffer_destroy,
        hbRaw.hb_buffer_set_direction, hbRaw.hb_buffer_set_script,
        hbRaw.hb_buffer_set_language, hbRaw.hb_buffer_set_flags,
        hbRaw.hb_buffer_guess_segment_properties, hbRaw.hb_buffer_set_cluster_level,
        hbRaw.hb_buffer_add_utf8, hbRaw.hb_buffer_get_length,
        hbRaw.hb_buffer_get_glyph_infos, hbRaw.hb_buffer_get_glyph_positions,
        hbRaw.hb_shape, hbRaw.hb_font_draw_glyph, hbRaw.hb_draw_funcs_create,
        hbRaw.hb_draw_funcs_destroy, hbRaw.hb_draw_funcs_set_move_to_func,
        hbRaw.hb_draw_funcs_set_line_to_func, hbRaw.hb_draw_funcs_set_quadratic_to_func,
        hbRaw.hb_draw_funcs_set_cubic_to_func, hbRaw.hb_draw_funcs_set_close_path_func,
        hbRaw.hb_draw_funcs_make_immutable,
      ):
        return false
      return hb.versionAtLeast(7, 0, 0)
    except hb.HarfBuzzLoadError, hb.FriBidiLoadError:
      return false

elif figdrawTextBackend in ["harfbuzzy", "hybrid"] and defined(
  feature.harfbuzzy.runtime
) and not defined(harfbuzzyStatic) and not defined(features.harfbuzzy.static):
  import pkg/harfbuzzy as hb
  hb.loadHarfbuzz()
  hb.loadFribidi()

proc currentTextBackend*(): TextBackendKind =
  when runtimeTextBackends:
    if not backendInitialized:
      backendInitialized = true
      if harfbuzzyAvailable():
        selectedBackend = TextBackendKind.Harfbuzzy
    selectedBackend
  elif figdrawTextBackend == "harfbuzzy":
    TextBackendKind.Harfbuzzy
  elif figdrawTextBackend == "uirelays":
    TextBackendKind.Uirelays
  elif figdrawTextBackend == "hybrid":
    TextBackendKind.Hybrid
  else:
    TextBackendKind.Pixie

proc selectTextBackend*(backend: TextBackendKind) =
  when runtimeTextBackends:
    backendInitialized = true
    selectedBackend = backend
  else:
    doAssert backend == currentTextBackend()

proc currentGlyphRaster*(): GlyphRasterBackend =
  if currentTextBackend() == TextBackendKind.Harfbuzzy:
    GlyphRasterBackend.Harfbuzz
  elif currentTextBackend() == TextBackendKind.Uirelays:
    GlyphRasterBackend.Uirelays
  else:
    GlyphRasterBackend.Pixie

proc effectiveGlyphRaster*(backend: GlyphRasterBackend): GlyphRasterBackend =
  if backend == GlyphRasterBackend.Automatic:
    when runtimeTextBackends:
      GlyphRasterBackend.Pixie
    else:
      currentGlyphRaster()
  else:
    backend
