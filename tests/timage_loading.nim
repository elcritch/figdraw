import std/[os, unittest]

import pkg/pixie as pixie except readImage

import figdraw/commons

suite "image loading":
  test "load png via figDataDir fallback":
    setFigDataDir(getCurrentDir() / "data")
    let flippy = readImage("arrow.png")
    require flippy.mipmaps.len > 0

    let expected = pixie.readImage(figDataDir() / "arrow.png")
    check flippy.mipmaps[0].width == expected.width
    check flippy.mipmaps[0].height == expected.height

  test "load flippy via figDataDir fallback":
    setFigDataDir(getCurrentDir() / "data")
    let flippy = readImage("arrow.flippy")
    require flippy.mipmaps.len > 0

    let expected = pixie.readImage(figDataDir() / "arrow.png")
    check flippy.mipmaps[0].width == expected.width
    check flippy.mipmaps[0].height == expected.height

  test "missing image returns empty":
    check readImage("does-not-exist.png").mipmaps.len == 0
