import std/[os, unittest]

import pkg/chroma
import pkg/pixie

import figdraw/commons
import figdraw/fignodes

import ./siwin_test_utils

proc makeAsymmetricImage(): Image =
  result = newImage(24, 24)
  let
    topPx = rgba(0, 0, 0, 255).rgbx()
    bottomPx = rgba(255, 230, 0, 255).rgbx()
    splitY = result.height div 3
  for y in 0 ..< result.height:
    let px = if y < splitY: topPx else: bottomPx
    for x in 0 ..< result.width:
      result[x, y] = px

proc makeSyntheticMsdfField(): Image =
  result = newImage(24, 24)
  let
    topPx = rgba(255, 255, 255, 255).rgbx()
    bottomPx = rgba(0, 0, 0, 255).rgbx()
    splitY = result.height div 3
  for y in 0 ..< result.height:
    let px = if y < splitY: topPx else: bottomPx
    for x in 0 ..< result.width:
      result[x, y] = px

proc rowProfile(img: Image, sampleRect: Rect): seq[int] =
  let
    x0 = max(0, sampleRect.x.int)
    y0 = max(0, sampleRect.y.int)
    x1 = min(img.width - 1, (sampleRect.x + sampleRect.w).int - 1)
    y1 = min(img.height - 1, (sampleRect.y + sampleRect.h).int - 1)
  if x1 < x0 or y1 < y0:
    return @[]

  result = newSeq[int](y1 - y0 + 1)
  for y in y0 .. y1:
    var sum = 0
    for x in x0 .. x1:
      let px = img[x, y]
      sum += (255 - px.r.int) + (255 - px.g.int) + (255 - px.b.int)
    result[y - y0] = sum

proc profileDiff(a, b: seq[int]): int =
  let n = min(a.len, b.len)
  var total = 0
  for i in 0 ..< n:
    total += abs(a[i] - b[i])
  total

proc profileDiffFlipped(a, b: seq[int]): int =
  let n = min(a.len, b.len)
  var total = 0
  for i in 0 ..< n:
    total += abs(a[i] - b[n - 1 - i])
  total

proc profileSpan(a: seq[int]): int =
  if a.len == 0:
    return 0
  var lo = high(int)
  var hi = low(int)
  for v in a:
    lo = min(lo, v)
    hi = max(hi, v)
  hi - lo

suite "siwin image/msdf invert render":
  test "NfInvertY keeps mirrored nkImage and nkMsdfImage upright":
    setFigUiScale(1.0'f32)

    let
      bitmapId = imgId("invert-test-bitmap")
      msdfId = imgId("invert-test-msdf")
    loadImage(bitmapId, makeAsymmetricImage())
    loadImage(msdfId, makeSyntheticMsdfField())

    let
      windowW = 720
      windowH = 520
      sampleW = 180.0'f32
      sampleH = 180.0'f32
      imageBaseRect = rect(40, 50, sampleW, sampleH)
      imageNoInvertRect = rect(260, 50, sampleW, sampleH)
      imageInvertRect = rect(480, 50, sampleW, sampleH)
      msdfBaseRect = rect(40, 270, sampleW, sampleH)
      msdfNoInvertRect = rect(260, 270, sampleW, sampleH)
      msdfInvertRect = rect(480, 270, sampleW, sampleH)

    proc mirroredInputRect(finalRect: Rect, h: float32): Rect =
      rect(finalRect.x, h - finalRect.y - finalRect.h, finalRect.w, finalRect.h)

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
          kind: nkImage,
          childCount: 0,
          zlevel: 1.ZLevel,
          screenBox: imageBaseRect,
          image: ImageStyle(id: bitmapId, fill: rgba(255, 255, 255, 255).color),
        )
      )

      discard list.addRoot(
        Fig(
          kind: nkMsdfImage,
          childCount: 0,
          zlevel: 1.ZLevel,
          screenBox: msdfBaseRect,
          msdfImage: MsdfImageStyle(
            id: msdfId,
            fill: rgba(0, 0, 0, 255).color,
            pxRange: 4.0'f32,
            sdThreshold: 0.5'f32,
          ),
        )
      )

      let mirroredRoot = list.addRoot(
        Fig(
          kind: nkTransform,
          childCount: 0,
          zlevel: 1.ZLevel,
          transform: TransformStyle(
            translation: vec2(0.0'f32, h),
            matrix: scale(vec3(1.0'f32, -1.0'f32, 1.0'f32)),
            useMatrix: true,
          ),
        )
      )

      discard list.addChild(
        mirroredRoot,
        Fig(
          kind: nkImage,
          childCount: 0,
          zlevel: 1.ZLevel,
          screenBox: mirroredInputRect(imageNoInvertRect, h),
          image: ImageStyle(id: bitmapId, fill: rgba(255, 255, 255, 255).color),
        ),
      )
      discard list.addChild(
        mirroredRoot,
        Fig(
          kind: nkImage,
          childCount: 0,
          zlevel: 1.ZLevel,
          flags: {NfInvertY},
          screenBox: mirroredInputRect(imageInvertRect, h),
          image: ImageStyle(id: bitmapId, fill: rgba(255, 255, 255, 255).color),
        ),
      )

      discard list.addChild(
        mirroredRoot,
        Fig(
          kind: nkMsdfImage,
          childCount: 0,
          zlevel: 1.ZLevel,
          screenBox: mirroredInputRect(msdfNoInvertRect, h),
          msdfImage: MsdfImageStyle(
            id: msdfId,
            fill: rgba(0, 0, 0, 255).color,
            pxRange: 4.0'f32,
            sdThreshold: 0.5'f32,
          ),
        ),
      )
      discard list.addChild(
        mirroredRoot,
        Fig(
          kind: nkMsdfImage,
          childCount: 0,
          zlevel: 1.ZLevel,
          flags: {NfInvertY},
          screenBox: mirroredInputRect(msdfInvertRect, h),
          msdfImage: MsdfImageStyle(
            id: msdfId,
            fill: rgba(0, 0, 0, 255).color,
            pxRange: 4.0'f32,
            sdThreshold: 0.5'f32,
          ),
        ),
      )

      result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
      result.layers[0.ZLevel] = list

    let outDir = ensureTestOutputDir()
    let outPath = outDir / "render_image_msdf_invert.png"
    if fileExists(outPath):
      removeFile(outPath)

    block renderOnce:
      var img: Image
      try:
        img = renderAndScreenshotOnce(
          makeRenders = makeRenderTree,
          outputPath = outPath,
          windowW = windowW,
          windowH = windowH,
          title = "figdraw test: image/msdf invert render (siwin)",
        )
      except ValueError:
        skip()
        break renderOnce

      check fileExists(outPath)
      check getFileSize(outPath) > 0

      let
        imageBaseProfile = rowProfile(img, imageBaseRect)
        imageNoInvertProfile = rowProfile(img, imageNoInvertRect)
        imageInvertProfile = rowProfile(img, imageInvertRect)
        msdfBaseProfile = rowProfile(img, msdfBaseRect)
        msdfNoInvertProfile = rowProfile(img, msdfNoInvertRect)
        msdfInvertProfile = rowProfile(img, msdfInvertRect)

      check imageBaseProfile.len > 0
      check imageNoInvertProfile.len > 0
      check imageInvertProfile.len > 0
      check msdfBaseProfile.len > 0
      check msdfNoInvertProfile.len > 0
      check msdfInvertProfile.len > 0

      check profileSpan(imageBaseProfile) > 500
      check profileSpan(msdfBaseProfile) > 500

      let
        imageNoInvertDirect = profileDiff(imageBaseProfile, imageNoInvertProfile)
        imageNoInvertFlipped =
          profileDiffFlipped(imageBaseProfile, imageNoInvertProfile)
        imageInvertDirect = profileDiff(imageBaseProfile, imageInvertProfile)
        imageInvertFlipped = profileDiffFlipped(imageBaseProfile, imageInvertProfile)
      check imageNoInvertFlipped < imageNoInvertDirect
      check imageInvertDirect <= imageInvertFlipped

      let
        msdfNoInvertDirect = profileDiff(msdfBaseProfile, msdfNoInvertProfile)
        msdfNoInvertFlipped = profileDiffFlipped(msdfBaseProfile, msdfNoInvertProfile)
        msdfInvertDirect = profileDiff(msdfBaseProfile, msdfInvertProfile)
        msdfInvertFlipped = profileDiffFlipped(msdfBaseProfile, msdfInvertProfile)
      check msdfNoInvertFlipped < msdfNoInvertDirect
      check msdfInvertDirect <= msdfInvertFlipped
