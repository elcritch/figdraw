import std/[os, unittest]

import pkg/pixie

import figdraw/commons
import figdraw/opengl/glcontext as glctx

suite "image loading":
  test "load png via figDataDir fallback":
    setFigDataDir(getCurrentDir() / "data")
    var ctx: glctx.Context
    let flippy = ctx.loadImage("arrow.png")
    require flippy.mipmaps.len > 0

    let expected = readImage(figDataDir() / "arrow.png")
    check flippy.mipmaps[0].width == expected.width
    check flippy.mipmaps[0].height == expected.height

  test "load flippy via figDataDir fallback":
    setFigDataDir(getCurrentDir() / "data")
    var ctx: glctx.Context
    let flippy = ctx.loadImage("arrow.flippy")
    require flippy.mipmaps.len > 0

    let expected = readImage(figDataDir() / "arrow.png")
    check flippy.mipmaps[0].width == expected.width
    check flippy.mipmaps[0].height == expected.height

  test "missing image returns empty":
    var ctx: glctx.Context
    check ctx.loadImage("does-not-exist.png").mipmaps.len == 0
