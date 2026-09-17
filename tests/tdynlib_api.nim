import std/[unittest, unicode]

import pkg/bumpy as bumpy

when defined(useNativeDynlib):
  import std/[os, strutils, tempfiles]
  import pkg/chroma as chroma
  import pkg/vmath as vmath
  import figdraw/extras/systemfonttypes as systemfonttypes
  from figdraw/common/fonttypes import nil
  import figdraw
  from figdraw_native_abi import nil

  proc loadExactTypefaceForCompileCheck(file: SystemTypefaceFile): TypefaceId {.used.} =
    loadTypeface(file)

  proc exactFontForCompileCheck(
      typeface: SystemTypeface, size: float32
  ): FigFont {.used.} =
    typeface.fontWithSize(size)

suite "native dynlib API":
  when defined(useNativeDynlib):
    test "uses shared Nim types directly without boundary casts":
      doAssert figdraw_native_abi.Rect is bumpy.Rect
      doAssert figdraw_native_abi.Vec2 is vmath.Vec2
      doAssert figdraw_native_abi.IVec2 is vmath.IVec2
      doAssert figdraw_native_abi.Mat4 is vmath.Mat4
      doAssert figdraw_native_abi.Color is chroma.Color
      doAssert figdraw_native_abi.ColorRGBA is chroma.ColorRGBA
      doAssert figdraw_native_abi.ColorRGBX is chroma.ColorRGBX
      doAssert figdraw_native_abi.Rune is unicode.Rune
      doAssert figdraw_native_abi.FontVariation is fonttypes.FontVariation
      doAssert figdraw_native_abi.SystemTypefaceFile is
        systemfonttypes.SystemTypefaceFile
      doAssert figdraw_native_abi.SystemTypeface is systemfonttypes.SystemTypeface
      doAssert typeof(default(GlyphArrangement).lines) is seq[Slice[int]]
      doAssert typeof(default(Fig).selectionRange) is Slice[int16]
      doAssert DirectionCorners is figdraw_native_abi.DirectionCorners
      doAssert CornerRadii is array[DirectionCorners, uint16]
      doAssert not declared(IntSlice)
      doAssert not declared(FigSelectionRange)
      doAssert not declared(toNativeVec2)
      doAssert not declared(toNativeIVec2)
      doAssert not declared(toNativeMat4)
      doAssert not declared(toNativeColor)
      doAssert not declared(toNativeRune)
      doAssert not declared(toNativeIntSlice)
      doAssert not declared(toNativeSelectionRange)
      doAssert not declared(utf8RunesFromRunes)
      doAssert not declared(newPixieImage)
      doAssert not declared(copyImage)
      doAssert not declared(readPixieImage)
      doAssert not declared(putFigImage)
      doAssert not declared(replaceFigImage)
      doAssert not declared(imageWidth)
      doAssert not declared(imageHeight)
      doAssert not declared(imagePixel)
      doAssert not declared(setImagePixel)
      doAssert not declared(fillImage)
      doAssert not declared(siwinSetIcon)
      doAssert not declared(siwinStartInteractiveMove)
      doAssert not declared(siwinStartInteractiveResize)
      doAssert not declared(siwinShowWindowMenu)
      doAssert SiwinRenderer is figdraw_native_abi.SiwinRenderer
      doAssert SiwinRenderBackend is figdraw_native_abi.SiwinRenderBackend
      doAssert not declared(NativeSiwinApp)
      doAssert SiwinPresentationTarget is figdraw_native_abi.SiwinPresentationTarget
      doAssert typeof(newFigSiwinApp(default(Window), 192, 1.0)) is SiwinRenderer
      doAssert not compiles(default(SiwinRenderer).backendState)
      doAssert not compiles(default(SiwinRenderer).ctx)
      doAssert not compiles(default(SiwinRenderBackend).window)
      doAssert not compiles(default(SiwinRenderBackend).dedicatedRender)
      doAssert not compiles(default(SiwinRenderBackend).metalLayer)
      doAssert not compiles(default(SiwinRenderBackend).vulkanMetalLayer)
      doAssert not compiles(default(SiwinPresentationTarget).metalLayer)
      doAssert not declared(NSView)
      doAssert not declared(CAMetalLayer)
      doAssert not compiles(default(FontRef).value)
      doAssert not compiles(default(ImageMessageSubscription).inbox)

      let arrangement =
        GlyphArrangement(lines: @[2 .. 5], arrangedGlyphs: newSeq[ArrangedGlyph](6))
      let ranges: seq[Slice[int]] = figdraw_native_abi.lineGlyphRanges(arrangement)
      check ranges == @[2 .. 5]
      check Fig(kind: nkText, selectionRange: 1'i16 .. 3'i16).selectionRange ==
        1'i16 .. 3'i16
      check figdraw_native_abi.fill(chroma.rgba(12, 34, 56, 255)).color ==
        chroma.rgba(12, 34, 56, 255)

      var matrix = mat4()
      matrix[0, 1] = 3.0'f32
      var list = RenderList()
      discard figdraw_native_abi.addRoot(
        list,
        Fig(
          kind: nkTransform,
          transform:
            TransformStyle(translation: vec2(4, 5), matrix: matrix, useMatrix: true),
        ),
      )
      check list.nodes[0].transform.translation == vec2(4, 5)
      check list.nodes[0].transform.matrix == matrix

      var renders = newRenders()
      figdraw_native_abi.`[]`(renders, 0.ZLevel).nodes.add Fig(kind: nkRectangle)
      check renders.len(0.ZLevel) == 1

    test "uses the direct backend enum naming routine":
      check figdraw_native_abi.backendName(rbOpenGL) == "OpenGL"
      check figdraw_native_abi.backendName(rbMetal) == "Metal"
      check figdraw_native_abi.backendName(rbVulkan) == "Vulkan"
      doAssert not declared(siwinBackendKind)

    test "exports typed renderer routines directly":
      const generatedAbi = staticRead("../bin/figdraw_native_abi.nim")
      check "darwin/" notin generatedAbi
      check "metalx/" notin generatedAbi
      check "SiwinMetalLayerHandle" notin generatedAbi
      for name in ["BackendContext", "GlContext", "VulkanContext", "MetalContext"]:
        check name notin generatedAbi
      for name in [
        "backendKind", "setTextLcdFiltering", "textLcdFiltering",
        "setTextSubpixelPositioning", "textSubpixelPositioning",
        "setTextSubpixelGlyphVariants", "textSubpixelGlyphVariants",
      ]:
        var found = false
        for line in generatedAbi.splitLines():
          if line.startsWith("proc " & name & "*(renderer: SiwinRenderer"):
            check "importc: \"binny_generic_" in line
            found = true
        check found

      for prefix in ["proc `[]=`*(image: Image", "proc fill*(image: Image"]:
        var found = false
        for line in generatedAbi.splitLines():
          if line.startsWith(prefix):
            check "importc: \"binny_generic_" in line
            found = true
        check found

      for prefix in [
        "proc setupBackend*(renderer: SiwinRenderer",
        "proc beginFrame*(renderer: SiwinRenderer",
        "proc renderFrame*(renderer: SiwinRenderer",
        "proc endFrame*(renderer: SiwinRenderer",
        "proc presentationTarget*(renderer: SiwinRenderer",
        "proc updatePresentationTarget*(target: SiwinPresentationTarget",
        "proc backendSupportsDedicatedRenderThread*(kind: RendererBackendKind",
        "proc supportsDedicatedRenderThread*(renderer: SiwinRenderer",
        "proc useDedicatedRenderThread*(renderer: SiwinRenderer",
      ]:
        var found = false
        for line in generatedAbi.splitLines():
          if line.startsWith(prefix):
            check "importc:" in line
            found = true
        check found

      doAssert compiles(
        block:
          let renderer = default(figdraw_native_abi.SiwinRenderer)
          discard figdraw_native_abi.backendSupportsDedicatedRenderThread(rbOpenGL)
          discard figdraw_native_abi.supportsDedicatedRenderThread(renderer)
          let target = figdraw_native_abi.presentationTarget(renderer)
          figdraw_native_abi.updatePresentationTarget(target, default(Window))
          figdraw_native_abi.useDedicatedRenderThread(renderer)
      )

    test "uses generated Siwin types without the legacy bridge records":
      const generatedAbi = staticRead("../bin/figdraw_native_abi.nim")
      for line in generatedAbi.splitLines():
        if line.startsWith("import "):
          check "siwin" notin line
      doAssert Window is figdraw_native_abi.Window
      doAssert WindowEventsHandler is figdraw_native_abi.WindowEventsHandler
      doAssert PopupPlacement is figdraw_native_abi.PopupPlacement
      doAssert not declared(NativeWindowSize)
      doAssert not declared(NativeLogicalSize)
      doAssert not declared(NativeWindowVisualRegion)
      doAssert not declared(NativePopupPlacement)
      doAssert not declared(PopupConstraintAdjustments)
      doAssert not declared(WindowVisualCapabilities)
      doAssert not declared(FigFlagSet)
      doAssert not declared(NativeCloseCallback)
      doAssert not declared(siwinSetEventCallbacks)
      doAssert not declared(siwinWindowStep)
      doAssert not declared(siwinWindowHandle)
      doAssert compiles(
        block:
          let window = figdraw_native_abi.newSiwinWindow(
            ivec2(320, 220), false, "raw Siwin", true, 0, true, false, false
          )
          window.eventsHandler = WindowEventsHandler(
            onResize: proc(event: ResizeEvent) =
              discard event.size,
            onTextInput: proc(event: TextInputEvent) =
              discard event.text,
          )
          figdraw_native_abi.firstStep(window, false)
          figdraw_native_abi.`size=`(window, ivec2(400, 300))
          discard figdraw_native_abi.clipboard(window).text()
          discard figdraw_native_abi.`[]`(window.clipboard(), "text/plain")
          figdraw_native_abi.startInteractiveMove(window, some(vec2(10, 20)))
          figdraw_native_abi.startInteractiveResize(window, Edge.top, none(Vec2))
          figdraw_native_abi.showWindowMenu(window, none(Vec2))
          figdraw_native_abi.`icon=`(window, nil)
          figdraw_native_abi.`icon=`(window, PixelBuffer())
          window.startInteractiveMove(vec2(10, 20))
          window.startInteractiveResize(Edge.top, vec2(10, 20))
          window.showWindowMenu(vec2(10, 20))
          window.icon = newImage(1, 1)
          window.icon = nil
          let placement = PopupPlacement(size: ivec2(80, 60))
          discard figdraw_native_abi.newSiwinPopupWindow(window, placement, true, true)
          figdraw_native_abi.close(window)
      )

    test "converts positions and borrows icon pixels without producer bridges":
      let position: Option[Vec2] = vec2(3, 5)
      check position.get() == vec2(3, 5)
      let
        image = newImage(2, 3)
        buffer = image.toPixelBuffer()
      check buffer.data == image.data[0].addr
      check buffer.size == ivec2(2, 3)
      check buffer.format == rgbx_32bit
      check toPixelBuffer(Image(nil)).data == nil
      check toPixelBuffer(Image()).data == nil

    test "supports elliptical corners and drawable ellipses":
      let
        horizontal = [4'u16, 6'u16, 8'u16, 10'u16]
        vertical = [2'u16, 3'u16, 4'u16, 5'u16]
        radii = initCornerRadii2D(horizontal, vertical)
        ellipse = drawableEllipse(vec2(12.0'f32, 18.0'f32), vec2(24.0'f32, 10.0'f32))

      check not radii.isCircular()
      check initCornerRadii2D(horizontal).isCircular()
      check ellipse.kind == dkEllipse
      check ellipse.ellipseCenter == vec2(12.0'f32, 18.0'f32)
      check ellipse.ellipseRadii == vec2(24.0'f32, 10.0'f32)
      let bezier = drawableBezier([vec2(0, 0), vec2(1, 2), vec2(3, 4)], steps = 8'u16)
      check bezier.kind == dkBezier
      check bezier.controls.len == 3
      check bezier.controls[1] == vec2(1.0'f32, 2.0'f32)

      var node = Fig(kind: nkRectangle)
      node.corners = horizontal
      node.cornerRadiiY = vertical
      node.flags.incl NfEllipticalCorners
      check NfEllipticalCorners in node.flags
      node.corners = [4.0'f32, 6.0'f32, 8.0'f32, 10.0'f32]
      check node.corners[dcTopLeft] == 4'u16
      check node.corners[dcBottomRight] == 10'u16
      var enumRadii: array[DirectionCorners, float32]
      enumRadii[dcTopRight] = 12.0'f32
      node.corners = enumRadii
      check node.corners[dcTopRight] == 12'u16

    test "provides source-compatible image and backdrop values":
      var imageRef: ImageRef
      imageRef = nil
      check imageRef == default(ImageRef)

      var renderer: SiwinRenderer
      var imageHandle: Image
      check renderer.isNil
      check imageHandle.isNil

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
        textStorage = utf8RunesFromText(source)
        storage: Utf8Runes = sourceRunes

      check textStorage.stringValue() == source
      check storage.len == sourceRunes.len
      check not storage.isEmpty
      check figdraw.`[]`(storage, 1) == sourceRunes[1]
      check figdraw.`[]`(storage, 2 .. 4).stringValue() == "λ 😀"
      check storage.stringValue() == source
      check figdraw.toRunes(storage) == sourceRunes
      check storage == sourceRunes

      let arrangement = GlyphArrangement(sourceRunes: sourceRunes, runes: sourceRunes)
      check arrangement.sourceRunes.len == sourceRunes.len
      check arrangement.runes.stringValue() == source
      check textBackend() == figdrawTextBackend
      check textBackendFeatures().len > 0
      check supportedFontFileExtensions().len > 0
      check storage.copyUtf8Runes().stringValue() == source

    test "uses direct UTF-8 constructors with shared Rune and sink string arguments":
      let
        source = "A λ 😀"
        sourceRunes = source.toRunes()
        fromRunes = figdraw_native_abi.initUtf8Runes(sourceRunes)
        fromArray = figdraw_native_abi.initUtf8Runes([Rune(0x3bb), Rune(0x1f600)])

      check figdraw_native_abi.toRunes(fromRunes) == sourceRunes
      check figdraw_native_abi.`[]`(fromRunes, 2) == Rune(0x3bb)
      check figdraw_native_abi.`[]`(fromRunes, 2 .. 4).stringValue() == "λ 😀"
      check fromArray.stringValue() == "λ😀"
      check sourceRunes == source.toRunes()

      var retainedText = source
      let fromRetainedText = figdraw_native_abi.initUtf8Runes(retainedText)
      retainedText[0] = 'B'
      check fromRetainedText.stringValue() == source
      check retainedText == "B λ 😀"

      var ownedText = source & "!"
      let fromOwnedText = figdraw_native_abi.initUtf8Runes(move(ownedText))
      check fromOwnedText.stringValue() == source & "!"
      check ownedText.len == 0
      check figdraw_native_abi.initUtf8Runes(newSeq[Rune]()).isEmpty
      check figdraw_native_abi.initUtf8Runes("").isEmpty

    test "uses direct font helpers and shared image fields":
      let
        font = fontWithSize(TypefaceId(17), 20.0'f32)
        color = rgba(12, 34, 56, 255)
        style = figdraw_native_abi.fs(font, fill(color))
        styledText = fsp(font, fill(color), "direct span")
        image = newImage(2, 3)

      check uint64(font.typefaceId) == 17'u64
      check font.size == 20.0'f32
      check style.color.color == color
      check fs(font).color.color == rgba(0, 0, 0, 255)
      check styledText[0].font.size == font.size
      check styledText[1] == "direct span"
      check span(font, fill(color), "alias span")[1] == "alias span"
      check image.width == 2
      check image.height == 3

      image.fill(color)
      check image[1, 2] == color
      let copiedImage = image.copy()
      copiedImage[1, 2] = rgba(90, 80, 70, 255)
      check copiedImage[1, 2] == rgba(90, 80, 70, 255)
      check image[1, 2] == color
      let decodedImage = decodeImage(image.encodePng())
      check decodedImage.width == image.width
      check decodedImage.height == image.height
      check decodedImage[1, 2] == color

      let imageId = imgId("native-direct-upload")
      figdraw_native_abi.loadImage(imageId, image)
      check image.width == 2
      check image[1, 2] == color
      figdraw_native_abi.replaceImage(imageId, copiedImage)
      check copiedImage[1, 2] == rgba(90, 80, 70, 255)
      var ownedImage = newImage(2, 3)
      figdraw_native_abi.loadImage(imageId, move(ownedImage))
      check ownedImage.isNil
      clearFigImage(imageId)

    test "loads shared system typeface metadata through direct native routines":
      let
        file =
          initSystemTypefaceFile(currentSourcePath().parentDir / "../data/Ubuntu.ttf")
        selection = initSystemTypeface(file, [FontVariation(tag: "wght", value: 450)])
        loaded = figdraw_native_abi.loadTypeface(file)
        font = figdraw_native_abi.fontWithSize(selection, 20.0'f32)
      check uint64(font.typefaceId) == uint64(loaded)
      check font.size == 20.0'f32
      check font.variations == selection.variations
      var independent = font
      independent.variations[0].value = 600
      check font.variations[0].value == 450
      check selection.variations[0].value == 450

    test "uses direct Pixie file codecs and preserves alpha conversion":
      let directory = createTempDir("figdraw-native-codecs-", "")
      try:
        let
          path = directory / "image.png"
          image = figdraw_native_abi.newImage(2, 2)
          color = rgba(64, 32, 16, 128)
        figdraw_native_abi.fill(image, color)
        let pixel = figdraw_native_abi.`[]`(image, 1, 1)
        doAssert typeof(pixel) is chroma.ColorRGBX
        doAssert typeof(image[1, 1]) is chroma.ColorRGBA
        check pixel == chroma.ColorRGBX(r: 32, g: 16, b: 8, a: 128)
        check pixel.rgba() == color
        check image[1, 1] == color
        for (x, y) in [(-1, 0), (0, -1), (image.width, 0), (0, image.height)]:
          check figdraw_native_abi.`[]`(image, x, y) == chroma.ColorRGBX()
          check image[x, y] == rgba(0, 0, 0, 0)
        figdraw_native_abi.`[]=`(image, -1, 0, rgba(255, 255, 255, 255))
        check image[0, 0] == color
        let copy = figdraw_native_abi.copy(image)
        figdraw_native_abi.`[]=`(copy, 0, 0, rgba(255, 255, 255, 255))
        check image[0, 0] == color
        figdraw_native_abi.writeFile(image, path)
        let loaded = figdraw_native_abi.readImage(path)
        check loaded.width == 2
        check loaded.height == 2
        check loaded[1, 1] == color
        check decodeImage(figdraw_native_abi.encodePng(image))[1, 1] == color
      finally:
        removeFile(directory / "image.png")
        removeDir(directory)

    test "direct scale helpers use producer state with shared vector and rect types":
      let previousScale = figUiScale()
      try:
        setFigUiScale(2.0'f32)
        check scaled(vec2(3, 4)) == vec2(6, 8)
        check descaled(vec2(6, 8)) == vec2(3, 4)
        check scaled(ivec2(3, 4)) == ivec2(6, 8)
        check scaled(bumpy.rect(1, 2, 3, 4)) == bumpy.rect(2, 4, 6, 8)
        check descaled(bumpy.rect(2, 4, 6, 8)) == bumpy.rect(1, 2, 3, 4)
        check scaled(3.0'f32) == 6.0'f32
        check descaled(6.0'f32) == 3.0'f32
      finally:
        setFigUiScale(previousScale)

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
          let lines: seq[Slice[int]] = arrangement.lineGlyphRanges()
          let selectionRects: seq[bumpy.Rect] = arrangement.selectionRectsFor(0 .. 1)
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
          window.title = "direct Siwin title"
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
