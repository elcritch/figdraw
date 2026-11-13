import std/unittest

import figdraw/common/fonttypes

suite "text backend information":
  test "reports the selected text backend":
    when runtimeTextBackends:
      check textBackend() in ["pixie", "harfbuzzy"]
    else:
      check textBackend() == figdrawTextBackend

  test "reports backend-specific text features":
    case textBackend()
    of "pixie":
      check textBackendFeatures() == @["pixie-typesetting", "pixie-rasterization"]
    of "harfbuzzy":
      check textBackendFeatures() ==
        @[
          "harfbuzz-shaping", "glyph-id-rasterization", "bidirectional-text",
          "font-fallback", "opentype-features", "font-variations",
        ]
    of "hybrid":
      check textBackendFeatures() ==
        @[
          "harfbuzz-shaping", "pixie-rasterization", "bidirectional-text",
          "font-fallback", "opentype-features", "font-variations",
        ]
    of "uirelays":
      check textBackendFeatures() ==
        @["platform-measurement", "platform-rasterization"]
    else:
      discard

  test "reports supported typeface file extensions":
    check supportedFontFileExtensions() == @[".ttf", ".otf", ".ttc", ".svg", ".otc"]
