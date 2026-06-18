import std/math

import pkg/chroma
import pkg/harfbuzzy/raw as hbraw
import pkg/pixie
import pkg/vmath

import ../fonttypes
import ../imgutils
import ../shared
import ../typefaces
import ./pixie_raster

const hbHeader = "hb.h"

type
  HbDrawFuncsObj {.importc: "hb_draw_funcs_t", header: hbHeader, incompleteStruct.} = object

  HbDrawStateObj {.importc: "hb_draw_state_t", header: hbHeader, incompleteStruct.} = object

  HbDrawFuncs = ptr HbDrawFuncsObj
  HbDrawState = ptr HbDrawStateObj

  HbDrawMoveToFunc = proc(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    toX, toY: cfloat,
    userData: pointer,
  ) {.cdecl.}

  HbDrawLineToFunc = proc(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    toX, toY: cfloat,
    userData: pointer,
  ) {.cdecl.}

  HbDrawQuadraticToFunc = proc(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    controlX, controlY, toX, toY: cfloat,
    userData: pointer,
  ) {.cdecl.}

  HbDrawCubicToFunc = proc(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    control1X, control1Y, control2X, control2Y, toX, toY: cfloat,
    userData: pointer,
  ) {.cdecl.}

  HbDrawClosePathFunc = proc(
    funcs: HbDrawFuncs, drawData: pointer, state: HbDrawState, userData: pointer
  ) {.cdecl.}

  DrawPathState = object
    path: Path

  HbFontHandles = object
    blob: hbraw.HbBlob
    face: hbraw.HbFace
    font: hbraw.HbFont

proc hb_draw_funcs_create(): HbDrawFuncs {.
  cdecl, importc: "hb_draw_funcs_create", dynlib: hbraw.hbLib
.}

proc hb_draw_funcs_destroy(
  funcs: HbDrawFuncs
) {.cdecl, importc: "hb_draw_funcs_destroy", dynlib: hbraw.hbLib.}

proc hb_draw_funcs_make_immutable(
  funcs: HbDrawFuncs
) {.cdecl, importc: "hb_draw_funcs_make_immutable", dynlib: hbraw.hbLib.}

proc hb_draw_funcs_set_move_to_func(
  funcs: HbDrawFuncs,
  callback: HbDrawMoveToFunc,
  userData: pointer,
  destroy: hbraw.HbDestroyFunc,
) {.cdecl, importc: "hb_draw_funcs_set_move_to_func", dynlib: hbraw.hbLib.}

proc hb_draw_funcs_set_line_to_func(
  funcs: HbDrawFuncs,
  callback: HbDrawLineToFunc,
  userData: pointer,
  destroy: hbraw.HbDestroyFunc,
) {.cdecl, importc: "hb_draw_funcs_set_line_to_func", dynlib: hbraw.hbLib.}

proc hb_draw_funcs_set_quadratic_to_func(
  funcs: HbDrawFuncs,
  callback: HbDrawQuadraticToFunc,
  userData: pointer,
  destroy: hbraw.HbDestroyFunc,
) {.cdecl, importc: "hb_draw_funcs_set_quadratic_to_func", dynlib: hbraw.hbLib.}

proc hb_draw_funcs_set_cubic_to_func(
  funcs: HbDrawFuncs,
  callback: HbDrawCubicToFunc,
  userData: pointer,
  destroy: hbraw.HbDestroyFunc,
) {.cdecl, importc: "hb_draw_funcs_set_cubic_to_func", dynlib: hbraw.hbLib.}

proc hb_draw_funcs_set_close_path_func(
  funcs: HbDrawFuncs,
  callback: HbDrawClosePathFunc,
  userData: pointer,
  destroy: hbraw.HbDestroyFunc,
) {.cdecl, importc: "hb_draw_funcs_set_close_path_func", dynlib: hbraw.hbLib.}

proc hb_font_draw_glyph_or_fail(
  font: hbraw.HbFont, glyph: hbraw.HbCodepoint, funcs: HbDrawFuncs, drawData: pointer
): hbraw.HbBool {.cdecl, importc: "hb_font_draw_glyph_or_fail", dynlib: hbraw.hbLib.}

proc hbTag(tag: string): hbraw.HbTag =
  if tag.len == 0 or tag.len > 4:
    raise newException(ValueError, "HarfBuzz tags must contain 1 to 4 bytes")
  hbraw.hb_tag_from_string(tag.cstring, cint(tag.len))

proc setVariations(font: hbraw.HbFont, variations: openArray[FontVariation]) =
  if variations.len == 0:
    return

  var rawVariations = newSeq[hbraw.HbVariation](variations.len)
  for i, variation in variations:
    rawVariations[i] =
      hbraw.HbVariation(tag: hbTag(variation.tag), value: cfloat(variation.value))
  hbraw.hb_font_set_variations(font, addr rawVariations[0], cuint(rawVariations.len))

proc drawPathState(drawData: pointer): ptr DrawPathState {.inline.} =
  cast[ptr DrawPathState](drawData)

proc drawMoveTo(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    toX, toY: cfloat,
    userData: pointer,
) {.cdecl.} =
  discard funcs
  discard state
  discard userData
  drawData.drawPathState().path.moveTo(toX.float32, toY.float32)

proc drawLineTo(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    toX, toY: cfloat,
    userData: pointer,
) {.cdecl.} =
  discard funcs
  discard state
  discard userData
  drawData.drawPathState().path.lineTo(toX.float32, toY.float32)

proc drawQuadraticTo(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    controlX, controlY, toX, toY: cfloat,
    userData: pointer,
) {.cdecl.} =
  discard funcs
  discard state
  discard userData
  drawData.drawPathState().path.quadraticCurveTo(
    controlX.float32, controlY.float32, toX.float32, toY.float32
  )

proc drawCubicTo(
    funcs: HbDrawFuncs,
    drawData: pointer,
    state: HbDrawState,
    control1X, control1Y, control2X, control2Y, toX, toY: cfloat,
    userData: pointer,
) {.cdecl.} =
  discard funcs
  discard state
  discard userData
  drawData.drawPathState().path.bezierCurveTo(
    control1X.float32, control1Y.float32, control2X.float32, control2Y.float32,
    toX.float32, toY.float32,
  )

proc drawClosePath(
    funcs: HbDrawFuncs, drawData: pointer, state: HbDrawState, userData: pointer
) {.cdecl.} =
  discard funcs
  discard state
  discard userData
  drawData.drawPathState().path.closePath()

proc createDrawFuncs(): HbDrawFuncs =
  result = hb_draw_funcs_create()
  if result == nil:
    raise newException(ValueError, "could not create HarfBuzz draw functions")

  hb_draw_funcs_set_move_to_func(result, drawMoveTo, nil, nil)
  hb_draw_funcs_set_line_to_func(result, drawLineTo, nil, nil)
  hb_draw_funcs_set_quadratic_to_func(result, drawQuadraticTo, nil, nil)
  hb_draw_funcs_set_cubic_to_func(result, drawCubicTo, nil, nil)
  hb_draw_funcs_set_close_path_func(result, drawClosePath, nil, nil)
  hb_draw_funcs_make_immutable(result)

proc destroy(handles: var HbFontHandles) =
  if handles.font != nil:
    hbraw.hb_font_destroy(handles.font)
    handles.font = nil
  if handles.face != nil:
    hbraw.hb_face_destroy(handles.face)
    handles.face = nil
  if handles.blob != nil:
    hbraw.hb_blob_destroy(handles.blob)
    handles.blob = nil

proc initHbFont(fontId: FontId): HbFontHandles =
  let
    font = getFigFont(fontId)
    source = getTypefaceSource(font.typefaceId)

  if source.data.len == 0:
    raise newException(ValueError, "typeface source data is empty")

  result.blob = hbraw.hb_blob_create(
    source.data.cstring,
    cuint(source.data.len),
    hbraw.HB_MEMORY_MODE_DUPLICATE,
    nil,
    nil,
  )
  if result.blob == nil:
    raise newException(ValueError, "could not create HarfBuzz blob")

  result.face = hbraw.hb_face_create(result.blob, 0)
  if result.face == nil:
    result.destroy()
    raise newException(ValueError, "could not create HarfBuzz face")

  result.font = hbraw.hb_font_create(result.face)
  if result.font == nil:
    result.destroy()
    raise newException(ValueError, "could not create HarfBuzz font")

  hbraw.hb_ot_font_set_funcs(result.font)
  let upem = hbraw.hb_face_get_upem(result.face)
  if upem > 0:
    hbraw.hb_font_set_scale(result.font, cint(upem), cint(upem))
  result.font.setVariations(font.variations)

proc drawGlyphPath(font: hbraw.HbFont, glyphId: FontGlyphId): Path =
  let funcs = createDrawFuncs()
  defer:
    hb_draw_funcs_destroy(funcs)

  var state = DrawPathState(path: newPath())
  let ok = hb_font_draw_glyph_or_fail(
    font, hbraw.HbCodepoint(uint32(glyphId)), funcs, addr state
  )
  if ok == 0:
    return nil
  state.path

proc imageBoundsFor(path: Path, fallbackSize: Vec2): Rect =
  var bounds = path.computeBounds().snapToPixels()
  if bounds.w <= 0 or bounds.h <= 0:
    bounds = rect(0, 0, fallbackSize.x, fallbackSize.y).snapToPixels()
  bounds.w = max(bounds.w, fallbackSize.x)
  bounds.h = max(bounds.h, fallbackSize.y)
  bounds

proc renderGlyphIdGlyph*(
    imageId: ImageId,
    fontId: FontId,
    glyphId: FontGlyphId,
    glyphRect: Rect,
    descent: float32,
    imageOffset: Vec2,
    lcdFiltering = false,
    subpixelVariant = 0,
    subpixelSteps = 10,
    upload = true,
): Image {.discardable.} =
  ## Renders one glyph by shaped font glyph id through HarfBuzz draw callbacks.
  var handles = initHbFont(fontId)
  defer:
    handles.destroy()

  let
    figFont = getFigFont(fontId)
    upem = hbraw.hb_face_get_upem(handles.face)
  if upem == 0:
    return nil

  var path = handles.font.drawGlyphPath(glyphId)
  if path == nil or ($path).len == 0:
    return nil

  let
    fontScale = figFont.size.getScaledFont() / upem.float32
    subpixelOffset =
      if subpixelVariant > 0:
        subpixelVariant.float32 / subpixelSteps.float32
      else:
        0.0'f32
    imageOffsetPx = imageOffset.scaled()
    baselineY = descent.scaled()
    transform =
      translate(vec2(subpixelOffset - imageOffsetPx.x, baselineY - imageOffsetPx.y)) *
      scale(vec2(fontScale, -fontScale))

  path.transform(transform)

  let
    fallbackSize =
      vec2(max(glyphRect.w.scaled(), 1.0'f32), max(glyphRect.h.scaled(), 1.0'f32))
    bounds = imageBoundsFor(path, fallbackSize)
    imageWidth = max(ceil(bounds.x + bounds.w).int, 1)
    imageHeight = max(ceil(bounds.y + bounds.h).int, 1)

  if imageWidth <= 0 or imageHeight <= 0:
    return nil

  try:
    var image = newImage(imageWidth, imageHeight)
    image.fillPath(path, parseSomePaint(rgba(255, 255, 255, 255)))
    if lcdFiltering:
      image.applyLcdFilter()

    if upload:
      loadImage(imageId, image)
    return image
  except PixieError:
    return nil
