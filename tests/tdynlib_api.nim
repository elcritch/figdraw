import std/[unittest, unicode]

import pkg/bumpy as bumpy

when defined(useNativeDynlib):
  import figdraw/dynlib
  import figdraw_native_abi except SystemTypefaceFile

  proc loadExactTypefaceForCompileCheck(file: SystemTypefaceFile): TypefaceId {.used.} =
    loadTypeface(file)

  proc exactFontForCompileCheck(
      typeface: SystemTypeface, size: float32
  ): FigFont {.used.} =
    typeface.fontWithSize(size)

suite "native dynlib API":
  when defined(useNativeDynlib):
    test "supports elliptical corners and drawable ellipses":
      let
        horizontal = [4'u16, 6'u16, 8'u16, 10'u16]
        vertical = [2'u16, 3'u16, 4'u16, 5'u16]
        radii = initCornerRadii2D(horizontal, vertical)
        ellipse = drawableEllipse(vec2(12.0'f32, 18.0'f32), vec2(24.0'f32, 10.0'f32))

      check not radii.isCircular()
      check initCornerRadii2D(horizontal).isCircular()
      check ellipse.kind == dkEllipse
      check ellipse.ellipseCenter.toVec2() == vec2(12.0'f32, 18.0'f32)
      check ellipse.ellipseRadii.toVec2() == vec2(24.0'f32, 10.0'f32)
      let bezier = drawableBezier([vec2(0, 0), vec2(1, 2), vec2(3, 4)], steps = 8'u16)
      check bezier.kind == dkBezier
      check bezier.controls.len == 3
      check bezier.controls[1].toVec2() == vec2(1.0'f32, 2.0'f32)

      var node = Fig(kind: nkRectangle)
      node.corners = horizontal
      node.cornerRadiiY = vertical
      node.flags.incl NfEllipticalCorners
      check NfEllipticalCorners in node.flags

    test "provides source-compatible image and backdrop values":
      var imageRef: ImageRef
      imageRef = nil
      check imageRef == default(ImageRef)

      var appHandle: NativeSiwinApp
      var imageHandle: Image
      check appHandle.raw == nil
      check imageHandle.raw == nil

      let
        region = WindowVisualRegion(pos: ivec2(8, 12), size: ivec2(160, 90))
        blur = initWindowBackdrop([region])
        material = initWindowBackdrop(wbmSidebar, [region])
      check blur.kind == wbkBlur
      check blur.regions == @[region]
      check material.kind == wbkMaterial
      check material.material == wbmSidebar

    test "keeps UTF-8 rune storage through the native facade":
      let
        source = "A λ 😀"
        sourceRunes = source.toRunes()
        storage: Utf8Runes = sourceRunes

      check storage.len == sourceRunes.len
      check not storage.isEmpty
      check dynlib.`[]`(storage, 1) == sourceRunes[1]
      check dynlib.`[]`(storage, 2 .. 4).stringValue() == "λ 😀"
      check storage.stringValue() == source
      check dynlib.toRunes(storage) == sourceRunes
      check storage == sourceRunes

      let arrangement = GlyphArrangement(sourceRunes: sourceRunes, runes: sourceRunes)
      check arrangement.sourceRunes.len == sourceRunes.len
      check arrangement.runes.stringValue() == source
      check textBackend() == figdrawTextBackend
      check textBackendFeatures().len > 0
      check supportedFontFileExtensions().len > 0
      check storage.copyUtf8Runes().stringValue() == source

    test "exports render tree and text layout helpers":
      doAssert compiles(
        block:
          var list = RenderList()
          let root = list.addRoot(Fig(kind: nkRectangle))
          discard list.insertRoot(Fig(kind: nkRectangle), 0)
          discard list.addChild(root, Fig(kind: nkRectangle))
          discard list.insertChild(root, Fig(kind: nkRectangle), 0)
          let added: seq[FigIdx] = list.addChildren(root, list)
          let inserted: seq[FigIdx] = list.insertChildren(root, list, 0)
          discard list.len()
          discard added
          discard inserted

          var renders = newRenders()
          let renderRoot = renders.addRoot(0.ZLevel, Fig(kind: nkRectangle))
          discard renders.addRoot(Fig(kind: nkRectangle))
          discard renders.addChild(0.ZLevel, renderRoot, Fig(kind: nkRectangle))
          let renderAdded: seq[FigIdx] = renders.addChildren(0.ZLevel, renderRoot, list)
          let renderInserted: seq[FigIdx] =
            renders.insertChildren(0.ZLevel, renderRoot, list, 0)
          renders.setLayer(1.ZLevel, list)
          discard renders.contains(0.ZLevel)
          discard figDataDir()
          registerStaticTypefaceData("compile-check", "", TTF)
          discard loadTypeface("compile-check")
          discard loadTypeface("compile-check", ["compile-check"])
          discard loadTypeface("compile-check", "", TTF)
          discard renderAdded
          discard renderInserted

          discard drawableLine(vec2(0, 0), vec2(1, 1))
          discard drawableCircle(vec2(0, 0), 1)
          discard drawableRect(bumpy.rect(0, 0, 10, 10), [0'u16, 0, 0, 0])
          discard drawableArc(vec2(0, 0), 1, 0, 1)
          discard typesetForMeasurement(
            bumpy.rect(0, 0, 10, 10),
            [(fs(FigFont()), "text")],
            FontHorizontal.Left,
            FontVertical.Top,
            false,
            false,
          )
          discard typeset(
            bumpy.rect(0, 0, 10, 10),
            [(fs(FigFont()), "text")],
            FontHorizontal.Left,
            FontVertical.Top,
            false,
            false,
          )
          discard figDashedRoundedRectBorder(
            bumpy.rect(0, 0, 10, 10),
            [0'u16, 0, 0, 0],
            fill(rgba(0, 0, 0, 255)),
            1,
            2,
            3,
            0,
            scButt,
            0,
          )
          discard figRoundedRectBorder(
            bumpy.rect(0, 0, 10, 10),
            [0'u16, 0, 0, 0],
            fill(rgba(0, 0, 0, 255)),
            1,
            scButt,
            0,
          )
          discard figDottedRoundedRectBorder(
            bumpy.rect(0, 0, 10, 10),
            [0'u16, 0, 0, 0],
            fill(rgba(0, 0, 0, 255)),
            1,
            2,
            0,
            0,
          )

          let arrangement = GlyphArrangement()
          let glyphRange: Slice[int] = arrangement.glyphRangeFor(0 .. 1)
          let sourceRange: Slice[int] = arrangement.sourceRuneRangeAt(vec2(0, 0))
          let lines: seq[IntSlice] = arrangement.lineGlyphRanges()
          let selectionRects: seq[figdraw_native_abi.Rect] =
            arrangement.selectionRectsFor(0 .. 1)
          let carets: seq[TextCaretPosition] = arrangement.caretPositionsFor(0)
          discard glyphRange
          discard sourceRange
          discard lines
          discard selectionRects
          discard carets
          discard arrangement.glyphCount()
          discard arrangement.glyphSourceRange(0)
          discard arrangement.glyphRect(0)
          discard arrangement.glyphFont(0)
          discard arrangement.layoutContentSize()
          discard arrangement.glyphIndexAt(vec2(0, 0))
          discard arrangement.sourceRuneCount()
          discard arrangement.nearestSourceRuneForCaretPoint(vec2(0, 0))
      )

    test "uses the native render and layout routines":
      var list = RenderList()
      let root = list.addRoot(Fig(kind: nkRectangle))
      check list.len == 1

      let emptyList = RenderList()
      check list.addChildren(root, emptyList).len == 0
      check list.insertChildren(root, emptyList, 0).len == 0

      var renders = newRenders()
      let renderRoot = renders.addRoot(0.ZLevel, Fig(kind: nkRectangle))
      check renders.len(0.ZLevel) == 1
      check renders.addChildren(0.ZLevel, renderRoot, emptyList).len == 0
      check renders.insertChildren(0.ZLevel, renderRoot, emptyList, 0).len == 0

      check drawableLine(vec2(0, 0), vec2(1, 1)).kind == dkLine
      check drawableCircle(vec2(0, 0), 1).kind == dkCircle
      check drawableRect(bumpy.rect(0, 0, 10, 10), [0'u16, 0, 0, 0]).kind == dkRectangle
      check drawableArc(vec2(0, 0), 1, 0, 1).kind == dkArc
      let borderFill = fill(rgba(0, 0, 0, 255))
      check figRoundedRectBorder(
        bumpy.rect(0, 0, 10, 10), [0'u16, 0, 0, 0], borderFill, 1, scButt, 0
      ).kind == nkDrawable
      check figDashedRoundedRectBorder(
        bumpy.rect(0, 0, 10, 10), [0'u16, 0, 0, 0], borderFill, 1, 2, 3, 0, scButt, 0
      ).kind == nkDrawable
      check figDottedRoundedRectBorder(
        bumpy.rect(0, 0, 10, 10), [0'u16, 0, 0, 0], borderFill, 1, 2, 0, 0
      ).kind == nkDrawable

      let arrangement = GlyphArrangement()
      check arrangement.glyphCount() == 0
      check arrangement.glyphRangeFor(0 .. -1).a > arrangement.glyphRangeFor(0 .. -1).b
      check arrangement.lineGlyphRanges().len == 0
      check arrangement.selectionRectsFor(0 .. -1).len == 0
      check arrangement.caretPositionsFor(0).len == 1
      check arrangement.glyphRect(0).w == 0
      check arrangement.glyphIndexAt(vec2(0, 0)) == -1
      check arrangement.sourceRuneRangeAt(vec2(0, 0)).a == 0
      check arrangement.sourceRuneRangeAt(vec2(0, 0)).b == -1
      check arrangement.sourceRuneCount() == 0
      check arrangement.nearestSourceRuneForCaretPoint(vec2(0, 0)) == 0

    test "exposes the NimKit Siwin window surface":
      doAssert compiles(
        block:
          var window: Window
          discard window.inputDeviceScale()
          discard siwinBackendName()
          discard window.nativeWindowKey()
          discard window.title()
          window.minSize = ivec2(100, 80)
          window.maxSize = ivec2(1920, 1080)
          window.customTitlebar = true
          window.setTitleRegion(vec2(0, 0), vec2(200, 40))
          window.setInputRegion(vec2(0, 0), vec2(200, 120))
          window.setBorderWidth(6, 8, 12)
          window.startInteractiveMove(vec2(20, 20))
          window.startInteractiveResize(topLeft, vec2(20, 20))
          window.showWindowMenu(vec2(20, 20))
          window.cursor = arrow
          window.vsync = true
          window.separateTouch = true
          window.canBecomeKeyWindow = true
          window.canBecomeMainWindow = true
          discard window.visualCapabilities()
          discard window.trySetBackdrop(WindowBackdropConfig(kind: wbkNone))
      )
  else:
    test "requires useNativeDynlib":
      skip()
