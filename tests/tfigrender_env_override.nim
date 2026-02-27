import std/[os, unittest]

import figdraw/figrender

proc withCleanEnv(body: proc()) =
  let hadForce = existsEnv("FIGDRAW_FORCE_OPENGL")
  let oldForce = getEnv("FIGDRAW_FORCE_OPENGL")
  let hadBackend = existsEnv("FIGDRAW_BACKEND")
  let oldBackend = getEnv("FIGDRAW_BACKEND")
  let hadTextLcd = existsEnv("FIGDRAW_TEXT_LCD_FILTERING")
  let oldTextLcd = getEnv("FIGDRAW_TEXT_LCD_FILTERING")
  let hadTextLcdAlt2 = existsEnv("FIGDRAW_TEXT_LCD_FILTER")
  let oldTextLcdAlt2 = getEnv("FIGDRAW_TEXT_LCD_FILTER")
  let hadTextSubpixel = existsEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING")
  let oldTextSubpixel = getEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING")
  let hadTextSubpixelVariants = existsEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS")
  let oldTextSubpixelVariants = getEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS")
  defer:
    if hadForce:
      putEnv("FIGDRAW_FORCE_OPENGL", oldForce)
    else:
      delEnv("FIGDRAW_FORCE_OPENGL")
    if hadBackend:
      putEnv("FIGDRAW_BACKEND", oldBackend)
    else:
      delEnv("FIGDRAW_BACKEND")
    if hadTextLcd:
      putEnv("FIGDRAW_TEXT_LCD_FILTERING", oldTextLcd)
    else:
      delEnv("FIGDRAW_TEXT_LCD_FILTERING")
    if hadTextLcdAlt2:
      putEnv("FIGDRAW_TEXT_LCD_FILTER", oldTextLcdAlt2)
    else:
      delEnv("FIGDRAW_TEXT_LCD_FILTER")
    if hadTextSubpixel:
      putEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING", oldTextSubpixel)
    else:
      delEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING")
    if hadTextSubpixelVariants:
      putEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS", oldTextSubpixelVariants)
    else:
      delEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS")
  body()

suite "figrender env overrides":
  test "force opengl wins over backend selection":
    withCleanEnv proc() =
      putEnv("FIGDRAW_BACKEND", "vulkan")
      putEnv("FIGDRAW_FORCE_OPENGL", "1")
      check runtimeForceOpenGlRequested() == true

  test "backend=opengl enables override":
    withCleanEnv proc() =
      putEnv("FIGDRAW_BACKEND", "opengl")
      delEnv("FIGDRAW_FORCE_OPENGL")
      check runtimeForceOpenGlRequested() == true

  test "backend=vulkan without force does not enable opengl override":
    withCleanEnv proc() =
      putEnv("FIGDRAW_BACKEND", "vulkan")
      delEnv("FIGDRAW_FORCE_OPENGL")
      check runtimeForceOpenGlRequested() == false

  test "text flags default to disabled":
    withCleanEnv proc() =
      delEnv("FIGDRAW_TEXT_LCD_FILTERING")
      delEnv("FIGDRAW_TEXT_LCD_FILTER")
      delEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING")
      delEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS")
      check runtimeTextLcdFilteringRequested() == false
      check runtimeTextSubpixelPositioningRequested() == false
      check runtimeTextSubpixelGlyphVariantsRequested() == false

  test "text flags read env values":
    withCleanEnv proc() =
      putEnv("FIGDRAW_TEXT_LCD_FILTERING", "1")
      putEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING", "true")
      putEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS", "yes")
      check runtimeTextLcdFilteringRequested() == true
      check runtimeTextSubpixelPositioningRequested() == true
      check runtimeTextSubpixelGlyphVariantsRequested() == true

  test "text flags support glyph-variant alias":
    withCleanEnv proc() =
      putEnv("FIGDRAW_TEXT_LCD_FILTER", "yes")
      putEnv("FIGDRAW_TEXT_SUBPIXEL_POSITIONING", "on")
      putEnv("FIGDRAW_TEXT_SUBPIXEL_GLYPH_VARIANTS", "on")
      check runtimeTextLcdFilteringRequested() == true
      check runtimeTextSubpixelPositioningRequested() == true
      check runtimeTextSubpixelGlyphVariantsRequested() == true

  test "text runtime toggles are safe on non-OpenGL contexts":
    var renderer = newFigRenderer(BackendContext())
    check renderer.textLcdFiltering() == false
    check renderer.textSubpixelPositioning() == false
    check renderer.textSubpixelGlyphVariants() == false
    renderer.setTextLcdFiltering(true)
    renderer.setTextSubpixelPositioning(true)
    renderer.setTextSubpixelGlyphVariants(true)
    check renderer.textLcdFiltering() == false
    check renderer.textSubpixelPositioning() == false
    check renderer.textSubpixelGlyphVariants() == false
