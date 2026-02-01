import nodes/uinodes
import inputs
import fonttypes
import pixie

export fonttypes

when defined(nimscript):
  {.pragma: runtimeVar, compileTime.}
else:
  {.pragma: runtimeVar, global.}

when (NimMajor, NimMinor, NimPatch) < (2, 2, 0):
  {.passc: "-fpermissive -Wno-incompatible-function-pointer-types".}
  {.passl: "-fpermissive -Wno-incompatible-function-pointer-types".}

when not defined(nimscript):
  import fontutils
  export TypeFaceKinds

  proc getTypeface*(name: string): TypefaceId =
    ## loads typeface from pixie
    loadTypeface(name)

  proc getTypeface*(name, data: string, kind: TypeFaceKinds): TypefaceId =
    loadTypeface(name, data, kind)

  proc getLineHeight*(font: UiFont): UiScalar =
    getLineHeightImpl(font)

  proc getTypeset*(
      box: Box,
      spans: openArray[(UiFont, string)],
      hAlign = Left,
      vAlign = Top,
      minContent = false,
      wrap = true,
  ): GlyphArrangement =
    getTypesetImpl(box, spans, hAlign, vAlign, minContent, wrap)
