import std/unittest

import figdraw/commons

when UseOpenGlBackend:
  import std/[os, tables]

  import pkg/[chroma, opengl]
  import pkg/pixie

  import figdraw/windowing/windyshim
  import figdraw/fignodes
  import figdraw/figrender as glrenderer
  import figdraw/utils/glutils

  proc ensureTestOutputDir(subdir = "output"): string =
    result = getCurrentDir() / "tests" / subdir
    createDir(result)

  proc makeRenderTree(w, h: float32): Renders =
    var list = RenderList()
    discard list.addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: rect(0, 0, w, h),
        fill: rgba(255, 255, 255, 255),
      )
    )
    discard list.addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: rect(32, 24, 120, 80),
        fill: rgba(220, 40, 40, 255),
      )
    )

    result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
    result.layers[0.ZLevel] = list

  proc maxChannelDelta(px: ColorRGBX, r, g, b: uint8): int =
    max(abs(px.r.int - r.int), max(abs(px.g.int - g.int), abs(px.b.int - b.int)))

  proc renderOneFrameScreenshot(outputPath: string): Image =
    let window = newWindow(
      "figdraw test: opengl one-frame screenshot",
      ivec2(240'i32, 160'i32),
      visible = false,
    )
    startOpenGL(openglVersion)
    window.makeContextCurrent()
    window.visible = true

    try:
      if glGetString(GL_VERSION) == nil:
        raise newException(WindyError, "OpenGL context unavailable")

      let renderer = glrenderer.newFigRenderer(atlasSize = 512)
      pollEvents()
      let sz = window.logicalSize()
      var renders = makeRenderTree(sz.x, sz.y)
      renderer.renderFrame(renders, sz)
      glFinish()
      result = glrenderer.takeOneFrameScreenshot(renderer)
      result.writeFile(outputPath)
    finally:
      window.close()

suite "figrender one-frame screenshot":
  test "captures OpenGL back buffer instead of black front buffer":
    when UseOpenGlBackend:
      let outPath = ensureTestOutputDir() / "oneframe_opengl.png"
      if fileExists(outPath):
        removeFile(outPath)

      block renderOnce:
        var img: Image
        try:
          img = renderOneFrameScreenshot(outPath)
        except WindyError:
          skip()
          break renderOnce

        check fileExists(outPath)
        check getFileSize(outPath) > 0
        check img.width == 240
        check img.height == 160
        check img[12, 12].maxChannelDelta(255, 255, 255) <= 12
        check img[64, 48].maxChannelDelta(220, 40, 40) <= 12
    else:
      skip()
