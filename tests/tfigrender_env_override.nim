import std/[os, unittest]

import figdraw/commons
import figdraw/figrender

proc withCleanEnv(body: proc()) =
  let hadSoftwareGl = existsEnv("FIGDRAW_SOFTWARE_GL")
  let oldSoftwareGl = getEnv("FIGDRAW_SOFTWARE_GL")
  let hadLibGlSoftware = existsEnv("LIBGL_ALWAYS_SOFTWARE")
  let oldLibGlSoftware = getEnv("LIBGL_ALWAYS_SOFTWARE")
  let hadGalliumDriver = existsEnv("GALLIUM_DRIVER")
  let oldGalliumDriver = getEnv("GALLIUM_DRIVER")
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
    if hadSoftwareGl:
      putEnv("FIGDRAW_SOFTWARE_GL", oldSoftwareGl)
    else:
      delEnv("FIGDRAW_SOFTWARE_GL")
    if hadLibGlSoftware:
      putEnv("LIBGL_ALWAYS_SOFTWARE", oldLibGlSoftware)
    else:
      delEnv("LIBGL_ALWAYS_SOFTWARE")
    if hadGalliumDriver:
      putEnv("GALLIUM_DRIVER", oldGalliumDriver)
    else:
      delEnv("GALLIUM_DRIVER")
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
  when UseOpenGlBackend or UseOpenGlFallback:
    test "software OpenGL recognizes enabled values":
      withCleanEnv proc() =
        for value in ["1", "true", "TRUE", "yes", "on"]:
          putEnv("FIGDRAW_SOFTWARE_GL", value)
          check runtimeSoftwareOpenGlRequested() == true

    test "software OpenGL defaults to disabled":
      withCleanEnv proc() =
        delEnv("FIGDRAW_SOFTWARE_GL")
        check runtimeSoftwareOpenGlRequested() == false
        putEnv("FIGDRAW_SOFTWARE_GL", "0")
        check runtimeSoftwareOpenGlRequested() == false

    test "software renderer names are recognized":
      check isSoftwareOpenGlRenderer("llvmpipe (LLVM 18.1.8, 256 bits)")
      check isSoftwareOpenGlRenderer("Mesa X11 softpipe")
      check isSoftwareOpenGlRenderer("Google SwiftShader")
      check not isSoftwareOpenGlRenderer("AMD Radeon RX 7900")

    when defined(linux) or defined(bsd):
      test "software OpenGL configures Mesa":
        withCleanEnv proc() =
          putEnv("FIGDRAW_SOFTWARE_GL", "1")
          delEnv("LIBGL_ALWAYS_SOFTWARE")
          delEnv("GALLIUM_DRIVER")
          check configureSoftwareOpenGl() == true
          check getEnv("LIBGL_ALWAYS_SOFTWARE") == "true"
          check getEnv("GALLIUM_DRIVER") == "llvmpipe"

      test "software OpenGL preserves an explicit Gallium driver":
        withCleanEnv proc() =
          putEnv("FIGDRAW_SOFTWARE_GL", "1")
          putEnv("GALLIUM_DRIVER", "softpipe")
          check configureSoftwareOpenGl() == true
          check getEnv("GALLIUM_DRIVER") == "softpipe"
    elif defined(windows):
      test "software OpenGL selects LLVMpipe for Mesa WGL":
        withCleanEnv proc() =
          putEnv("FIGDRAW_SOFTWARE_GL", "1")
          delEnv("GALLIUM_DRIVER")
          check configureSoftwareOpenGl() == true
          check getEnv("GALLIUM_DRIVER") == "llvmpipe"
    else:
      test "software OpenGL reports unsupported native configuration":
        withCleanEnv proc() =
          putEnv("FIGDRAW_SOFTWARE_GL", "1")
          check configureSoftwareOpenGl() == false

  when UseOpenGlFallback and (UseMetalBackend or UseVulkanBackend):
    when defined(linux) or defined(bsd) or defined(windows):
      test "software OpenGL forces the OpenGL fallback backend":
        withCleanEnv proc() =
          putEnv("FIGDRAW_SOFTWARE_GL", "1")
          putEnv("FIGDRAW_BACKEND", "vulkan")
          putEnv("FIGDRAW_FORCE_OPENGL", "0")
          check runtimeForceOpenGlRequested() == true

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
  else:
    test "backend selection cannot enable an unavailable fallback":
      withCleanEnv proc() =
        putEnv("FIGDRAW_BACKEND", "opengl")
        putEnv("FIGDRAW_FORCE_OPENGL", "1")
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
