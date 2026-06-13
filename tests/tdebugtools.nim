import std/[options, tables, unittest]

import pkg/pixie

import figdraw/debugtools
import figdraw/fignodes

proc newRenders(): Renders =
  Renders(layers: initOrderedTable[ZLevel, RenderList]())

proc rectFig(
    box: Rect, color: ColorRGBA = rgba(255, 255, 255, 255), flags: set[FigFlags] = {}
): Fig =
  Fig(kind: nkRectangle, screenBox: box, fill: color, flags: flags)

suite "debug tools":
  test "figVisibility reports clipped out child":
    var renders = newRenders()
    let root =
      renders.addRoot(0.ZLevel, rectFig(rect(0, 0, 100, 100), flags = {NfClipContent}))
    let child = renders.addChild(
      0.ZLevel, root, rectFig(rect(120, 120, 20, 20), rgba(255, 0, 0, 255))
    )

    let visibility = renders.figVisibility(0.ZLevel, child)

    check visibility.visible == false
    check visibility.reason == fvClippedOut
    check visibility.clippedBounds.w == 0.0'f32
    check visibility.clippedBounds.h == 0.0'f32

  test "figVisibility keeps clipped bounds for partially clipped child":
    var renders = newRenders()
    let root =
      renders.addRoot(0.ZLevel, rectFig(rect(0, 0, 100, 100), flags = {NfClipContent}))
    let child = renders.addChild(
      0.ZLevel, root, rectFig(rect(80, 70, 40, 50), rgba(255, 0, 0, 255))
    )

    let visibility = renders.figVisibility(0.ZLevel, child)

    check visibility.visible == true
    check visibility.reason == fvVisible
    check visibility.clippedBounds == rect(80, 70, 20, 30)

  test "figVisibility reports simple opaque coverage by later node":
    var renders = newRenders()
    let back =
      renders.addRoot(0.ZLevel, rectFig(rect(10, 10, 40, 40), rgba(255, 0, 0, 255)))
    let front =
      renders.addRoot(0.ZLevel, rectFig(rect(0, 0, 100, 100), rgba(0, 0, 255, 255)))

    let backVisibility = renders.figVisibility(0.ZLevel, back)
    let frontVisibility = renders.figVisibility(0.ZLevel, front)

    check backVisibility.visible == false
    check backVisibility.reason == fvCovered
    check backVisibility.hasCoveredBy == true
    check backVisibility.coveredBy == FigLocation(zlevel: 0.ZLevel, index: front)
    check frontVisibility.visible == true

  test "topFigAtPoint returns front-most clipped hit":
    var renders = newRenders()
    discard
      renders.addRoot(0.ZLevel, rectFig(rect(0, 0, 100, 100), rgba(255, 0, 0, 255)))
    let front =
      renders.addRoot(1.ZLevel, rectFig(rect(20, 20, 20, 20), rgba(0, 0, 255, 255)))

    let hit = renders.topFigAtPoint(vec2(25, 25))

    check hit.isSome()
    check hit.get().location == FigLocation(zlevel: 1.ZLevel, index: front)

  test "colorAt samples images and returns transparent black outside bounds":
    var image = newImage(2, 2)
    image[1, 0] = rgba(10, 20, 30, 255)

    check image.colorAt(1, 0) == rgba(10, 20, 30, 255)
    check image.colorAt(-1, 0) == rgba(0, 0, 0, 0)
