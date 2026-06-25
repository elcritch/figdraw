import std/[os, tables, unittest]

import pkg/chroma
import pkg/pixie

import figdraw/commons
import figdraw/fignodes

import ./siwin_test_utils

proc maxChannelDelta(a: ColorRGBX, r, g, b: uint8): int =
  result = max(abs(a.r.int - r.int), max(abs(a.g.int - g.int), abs(a.b.int - b.int)))

proc sampleLogical(img: Image, x, y: int, logicalW, logicalH: int): ColorRGBX =
  let
    sx = img.width.float32 / logicalW.float32
    sy = img.height.float32 / logicalH.float32
    px = clamp(round(x.float32 * sx).int, 0, img.width - 1)
    py = clamp(round(y.float32 * sy).int, 0, img.height - 1)
  img[px, py]

template assertLogicalColor(
    img: Image, x, y, logicalW, logicalH: int, r, g, b: uint8, tol: int = 12
) =
  let px = img.sampleLogical(x, y, logicalW, logicalH)
  check px.maxChannelDelta(r, g, b) <= tol

proc addRect(
    list: var RenderList,
    parentIdx: FigIdx,
    rectBox: Rect,
    color: ColorRGBA,
    z: ZLevel,
    rectMask = false,
    corners = 0'u16,
) =
  var flags: set[FigFlags] = {}
  if rectMask:
    flags.incl NfRectMaskContent

  discard list.addChild(
    parentIdx,
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
      flags: flags,
    ),
  )

proc addRootRect(
    list: var RenderList,
    rectBox: Rect,
    color: ColorRGBA,
    z: ZLevel,
    rectMask = false,
    corners = 0'u16,
): FigIdx =
  var flags: set[FigFlags] = {}
  if rectMask:
    flags.incl NfRectMaskContent

  list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: color,
      corners: [corners, corners, corners, corners],
      flags: flags,
    )
  )

proc makeMixedRectMaskBatchRenderTree(w, h: float32): Renders =
  var list = RenderList()
  discard list.addRootRect(rect(0, 0, w, h), rgba(255, 255, 255, 255), 0.ZLevel)
  discard list.addRootRect(
    rect(32.0'f32, 48.0'f32, 96.0'f32, 80.0'f32), rgba(230, 70, 52, 255), 0.ZLevel
  )

  let maskIdx = list.addRootRect(
    rect(180.0'f32, 48.0'f32, 80.0'f32, 80.0'f32),
    rgba(218, 218, 218, 255),
    0.ZLevel,
    rectMask = true,
  )
  list.addRect(
    maskIdx,
    rect(150.0'f32, 72.0'f32, 150.0'f32, 34.0'f32),
    rgba(56, 168, 88, 255),
    0.ZLevel,
  )

  discard list.addRootRect(
    rect(310.0'f32, 48.0'f32, 96.0'f32, 80.0'f32), rgba(54, 118, 230, 255), 0.ZLevel
  )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc addClippedBand(
    list: var RenderList, rectBox: Rect, childColor: ColorRGBA, z: ZLevel
) =
  let parentIdx = list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: z,
      screenBox: rectBox,
      fill: rgba(0, 0, 0, 0),
      flags: {NfClipContent},
    )
  )
  list.addRect(parentIdx, rectBox, childColor, z)

proc makeSmallClipRenderTree(w, h: float32): Renders =
  var list = RenderList()
  discard list.addRootRect(rect(0, 0, w, h), rgba(255, 255, 255, 255), 0.ZLevel)
  list.addClippedBand(rect(32, 24, 180, 18), rgba(220, 40, 40, 255), 0.ZLevel)
  list.addClippedBand(rect(32, 56, 180, 24), rgba(56, 168, 88, 255), 0.ZLevel)
  list.addClippedBand(rect(32, 94, 180, 28), rgba(54, 118, 230, 255), 0.ZLevel)
  list.addClippedBand(rect(32, 136, 180, 32), rgba(210, 170, 46, 255), 0.ZLevel)

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

suite "siwin vulkan rect mask":
  test "keeps mixed masked and unmasked siblings in one batch":
    when UseVulkanBackend:
      const
        windowW = 480
        windowH = 180
      setFigUiScale(1.0)
      let outDir = ensureTestOutputDir()
      let outPath = outDir / "render_rect_mask_mixed_batch_vulkan.png"
      if fileExists(outPath):
        removeFile(outPath)

      block renderOnce:
        var rendered: Image
        try:
          rendered = renderAndScreenshotOnce(
            makeRenders = makeMixedRectMaskBatchRenderTree,
            outputPath = outPath,
            windowW = windowW,
            windowH = windowH,
            title = "figdraw test: vulkan mixed rect mask batch",
          )
        except ValueError:
          skip()
          break renderOnce

        check fileExists(outPath)
        check getFileSize(outPath) > 0

        assertLogicalColor(rendered, 74, 88, windowW, windowH, 230, 70, 52)
        assertLogicalColor(rendered, 160, 88, windowW, windowH, 255, 255, 255)
        assertLogicalColor(rendered, 204, 88, windowW, windowH, 56, 168, 88)
        assertLogicalColor(rendered, 276, 88, windowW, windowH, 255, 255, 255)
        assertLogicalColor(rendered, 336, 88, windowW, windowH, 54, 118, 230)
    else:
      skip()

  test "NfClipContent renders small clipped rectangle subtrees":
    when UseVulkanBackend:
      const
        windowW = 260
        windowH = 190
      setFigUiScale(1.0)
      let outDir = ensureTestOutputDir()
      let outPath = outDir / "render_small_clip_vulkan.png"
      if fileExists(outPath):
        removeFile(outPath)

      block renderOnce:
        var rendered: Image
        try:
          rendered = renderAndScreenshotOnce(
            makeRenders = makeSmallClipRenderTree,
            outputPath = outPath,
            windowW = windowW,
            windowH = windowH,
            title = "figdraw test: vulkan small clip",
          )
        except ValueError:
          skip()
          break renderOnce

        check fileExists(outPath)
        check getFileSize(outPath) > 0

        assertLogicalColor(rendered, 64, 32, windowW, windowH, 220, 40, 40)
        assertLogicalColor(rendered, 64, 68, windowW, windowH, 56, 168, 88)
        assertLogicalColor(rendered, 64, 108, windowW, windowH, 54, 118, 230)
        assertLogicalColor(rendered, 64, 152, windowW, windowH, 210, 170, 46)
    else:
      skip()
