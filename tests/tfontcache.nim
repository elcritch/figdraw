import std/[os, unittest]

import figdraw

suite "font cache public API":
  setup:
    resetFontCache(clearStaticTypefaces = true)
    setFigDataDir(getCurrentDir() / "data")

  teardown:
    resetFontCache(clearStaticTypefaces = true)

  test "reset clears registered fonts and metadata and permits reloading":
    let
      data = readFile(figDataDir() / "Ubuntu.ttf")
      id = loadTypeface("font-cache-test.ttf", data, TTF)
      font = fontWithSize(id, 20.0'f32)
      arrangement = typeset(
        rect(0, 0, 120, 40), [(fs(font), "A")], minContent = false, wrap = false
      )
      fontId = arrangement.fonts[0].fontId
      imageId = imgId("font-cache-independent-image")

    var glyphImageId: ImageId
    for glyph in arrangement.glyphs():
      glyphImageId = glyph.hash().ImageId
      break

    check getTypefaceInfo(id).family == "Ubuntu"
    check getTypefaceSource(id).data == data
    check getFigFont(fontId).typefaceId.int == id.int
    check hasTypeface(id)
    check hasFont(fontId)
    check hasImage(glyphImageId)
    loadImage(imageId, newImage(1, 1))

    resetFontCache()

    check not hasTypeface(id)
    check not hasFont(fontId)
    expect ValueError:
      discard getTypefaceSource(id)
    expect ValueError:
      discard getTypefaceInfo(id)
    expect ValueError:
      discard getFigFont(fontId)
    check not hasImage(glyphImageId)
    check hasImage(imageId)
    clearFigImage(imageId)
    check loadTypeface("font-cache-test.ttf", data, TTF).int == id.int
    check getTypefaceInfo(id).family == "Ubuntu"

  test "reset preserves static registrations by default":
    let
      name = "figdraw-reset-static-test-unique.ttf"
      data = readFile(figDataDir() / "Ubuntu.ttf")
    registerStaticTypefaceData(name, data, TTF)
    check hasStaticTypeface(name)
    discard loadTypeface(name)

    resetFontCache()
    let id = loadTypeface(name)
    check getTypefaceInfo(id).family == "Ubuntu"
    check hasStaticTypeface(name)

    resetFontCache(clearStaticTypefaces = true)
    check not hasTypeface(id)
    check not hasStaticTypeface(name)
