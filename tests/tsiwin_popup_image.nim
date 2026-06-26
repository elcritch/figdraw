import std/[os, tables, unittest]

import pkg/chroma
import pkg/pixie

import figdraw/commons
import figdraw/fignodes
import figdraw/figrender as figrender
import figdraw/windowing/siwinshim

when defined(linux) or defined(bsd):
  import siwin/platforms
  import siwin/platforms/x11/windowOpengl as x11WindowOpengl

when UseOpenGlBackend:
  import pkg/opengl
  import figdraw/utils/glutils

const FigdrawRoot = currentSourcePath.parentDir().parentDir()

proc ensureTestOutputDir(subdir = "output"): string =
  result = FigdrawRoot / "tests" / subdir
  createDir(result)

proc makePopupImageRenders(w, h: float32): Renders =
  var list = RenderList()
  let rootIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(160, 160, 160, 255),
    )
  )

  list.addChild(
    rootIdx,
    Fig(
      kind: nkImage,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(24, 20, 96, 96),
      image:
        ImageStyle(fill: rgba(255, 255, 255, 255).color, id: hash("img1.png").ImageId),
    ),
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  max(abs(a.r.int - r.int), max(abs(a.g.int - g.int), abs(a.b.int - b.int)))

proc renderPopupImageFrame(): Image =
  let globals = newSiwinGlobals(Platform.x11)
  var
    parent: Window
    popup: Window
  try:
    parent = globals.newOpenglWindow(
      size = ivec2(260, 180), title = "figdraw popup image parent"
    )
  except CatchableError as exc:
    raise newException(OSError, "OpenGL X11 window unavailable: " & exc.msg)

  try:
    parent.firstStep(makeVisible = false)
    parent.step()
    startOpenGL(openglVersion)

    let placement = PopupPlacement(
      anchorRectPos: ivec2(36, 48),
      anchorRectSize: ivec2(120, 32),
      size: ivec2(180, 140),
      anchor: bottomLeft,
      gravity: topLeft,
      offset: ivec2(0, 8),
    )
    popup = globals.newPopupWindow(parent, placement, grab = false)
    if not (popup of x11WindowOpengl.WindowX11Opengl):
      raise
        newException(ValueError, "X11 OpenGL popup did not preserve OpenGL window type")
    popup.firstStep(makeVisible = false)

    let renderer =
      figrender.newFigRenderer(atlasSize = 512, backendState = SiwinRenderBackend())
    renderer.setupBackend(popup)
    renderer.beginFrame()
    let sz = popup.logicalSize()
    var renders = makePopupImageRenders(sz.x, sz.y)
    renderer.renderFrame(renders, sz)
    glFinish()
    result = figrender.takeOneFrameScreenshot(renderer)
    renderer.endFrame()
  finally:
    if not popup.isNil:
      close popup
    if not parent.isNil:
      close parent

suite "figdraw siwin popup image render":
  test "renders an image into an X11 OpenGL popup":
    when UseOpenGlBackend and (defined(linux) or defined(bsd)):
      if Platform.x11 notin availablePlatforms():
        skip()

      setFigDataDir(FigdrawRoot / "data")
      discard loadImage("img1.png")
      let outPath = ensureTestOutputDir() / "siwin_popup_image.png"
      if fileExists(outPath):
        removeFile(outPath)

      block renderOnce:
        var img: Image
        try:
          img = renderPopupImageFrame()
        except OSError:
          skip()
          break renderOnce

        img.writeFile(outPath)
        check fileExists(outPath)
        check getFileSize(outPath) > 0
        check img.width == 180
        check img.height == 140

        let bg = (r: 160'u8, g: 160'u8, b: 160'u8)
        var differsFromBg = false
        for y in 28 .. 88:
          for x in 32 .. 96:
            if img[x, y].maxChannelDelta(bg.r, bg.g, bg.b) > 12:
              differsFromBg = true

        check differsFromBg
    else:
      skip()
