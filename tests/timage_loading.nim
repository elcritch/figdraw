import std/[hashes, os, tables, unittest]

import pkg/pixie as pixie except readImage

import figdraw/commons
import figdraw/common/typefaces
import figdraw/figrender
import figdraw/fignodes

type TestContext = ref object of BackendContext
  entries: Table[Hash, Rect]
  atlasEntryMeta: Table[Hash, AtlasEntryMeta]
  uploaded: seq[ImageId]
  removed: seq[ImageId]
  drawn: seq[Hash]
  resetCount: int

method entriesPtr*(ctx: TestContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method atlasEntryMetaPtr*(ctx: TestContext): ptr Table[Hash, AtlasEntryMeta] =
  ctx.atlasEntryMeta.addr

method putImage*(ctx: TestContext, imgObj: ImgObj) =
  ctx.uploaded.add(imgObj.id)
  ctx.entries[imgObj.id.Hash] = rect(0, 0, 1, 1)

method removeImage*(ctx: TestContext, id: ImageId) =
  ctx.removed.add(id)
  let key = id.Hash
  if key in ctx.atlasEntryMeta:
    let meta = ctx.atlasEntryMeta[key]
    if meta.kind == aekImage and meta.imageId == id:
      ctx.removeAtlasEntry(key)
  else:
    ctx.entries.del(key)

method clearImageAtlas*(ctx: TestContext) =
  inc ctx.resetCount
  ctx.entries.clear()
  ctx.atlasEntryMeta.clear()

method drawImage*(
    ctx: TestContext,
    path: Hash,
    pos: Vec2,
    colors: array[4, ColorRGBA],
    size: Vec2,
    flipY: bool,
) =
  if path in ctx.entries:
    ctx.drawn.add(path)

proc newTestContext(): TestContext =
  TestContext(
    entries: initTable[Hash, Rect](), atlasEntryMeta: initTable[Hash, AtlasEntryMeta]()
  )

proc newRenders(): Renders =
  Renders(layers: initOrderedTable[ZLevel, RenderList]())

proc drainImages(ctx: TestContext) =
  var renders = newRenders()
  ctx.renderRoot(renders)

proc recvImageMsg(kind: ImageMsgKind): ImageMsg =
  require tryRecvImageMsg(result)
  check result.kind == kind

proc retainImageOnThread(id: ImageId) {.thread.} =
  var owned = imageRef(id)
  discard owned.id

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

  test "clearImage drops logical cache and skips stale queued upload":
    let id = imgId("tests/timage_loading/stale")
    let ctx = newTestContext()
    clearImage(id)
    ctx.drainImages()

    loadImage(id, newImage(1, 1))
    check hasImage(id)

    clearImage(id)
    check not hasImage(id)
    ctx.drainImages()

    check ctx.uploaded.len == 0
    check id.Hash notin ctx.entries

  test "loadImage after clear uploads the current image":
    let id = imgId("tests/timage_loading/reload")
    let ctx = newTestContext()
    clearImage(id)
    ctx.drainImages()

    loadImage(id, newImage(1, 1))
    ctx.drainImages()
    check hasImage(id)
    check ctx.uploaded == @[id]
    check id.Hash in ctx.entries

    clearImage(id)
    check not hasImage(id)
    ctx.drainImages()
    check id.Hash notin ctx.entries

    loadImage(id, newImage(1, 1))
    ctx.drainImages()
    check hasImage(id)
    check ctx.uploaded == @[id, id]
    check id.Hash in ctx.entries

  test "loadImage path after clear uploads the current image":
    setFigDataDir(getCurrentDir() / "data")
    let
      path = "arrow.png"
      id = imgId(path)
      ctx = newTestContext()
    clearImage(id)
    ctx.drainImages()

    check loadImage(path) == id
    ctx.drainImages()
    check hasImage(id)
    check ctx.uploaded == @[id]
    check id.Hash in ctx.entries

    clearImage(id)
    check not hasImage(id)
    ctx.drainImages()
    check id.Hash notin ctx.entries

    check loadImage(path) == id
    ctx.drainImages()
    check hasImage(id)
    check ctx.uploaded == @[id, id]
    check id.Hash in ctx.entries

  test "clearImages drops logical cache and removes backend entries":
    let
      idA = imgId("tests/timage_loading/batch/a")
      idB = imgId("tests/timage_loading/batch/b")
      ctx = newTestContext()
    clearImages([idA, idB])
    ctx.drainImages()
    ctx.removed.setLen(0)

    loadImage(idA, newImage(1, 1))
    loadImage(idB, newImage(1, 1))
    ctx.drainImages()
    check hasImage(idA)
    check hasImage(idB)
    check idA.Hash in ctx.entries
    check idB.Hash in ctx.entries

    clearImages([idA, idB])
    check not hasImage(idA)
    check not hasImage(idB)
    ctx.drainImages()

    check ctx.removed == @[idA, idB]
    check idA.Hash notin ctx.entries
    check idB.Hash notin ctx.entries

  test "drawing a cleared image does not crash":
    let
      id = imgId("tests/timage_loading/draw-cleared")
      ctx = newTestContext()
    var renders = newRenders()
    discard renders.addRoot(
      0.ZLevel,
      Fig(
        kind: nkImage,
        screenBox: rect(0, 0, 16, 16),
        image: ImageStyle(id: id, fill: rgba(255, 255, 255, 255).color),
      ),
    )

    clearImage(id)
    ctx.drainImages()

    loadImage(id, newImage(1, 1))
    ctx.renderRoot(renders)
    check ctx.drawn == @[id.Hash]

    clearImage(id)
    ctx.renderRoot(renders)
    check ctx.drawn == @[id.Hash]
    check id.Hash notin ctx.entries

  test "clearImage only removes entries marked as that image":
    let
      id = imgId("tests/timage_loading/metadata/protected")
      key = id.Hash
      fontId = FontId(Hash(101))
      typefaceId = TypefaceId(Hash(201))
      ctx = newTestContext()

    ctx.entries[key] = rect(0, 0, 1, 1)
    ctx.markGlyphEntry(key, fontId, typefaceId)
    clearImage(id)
    ctx.drainImages()
    check key in ctx.entries
    check ctx.atlasEntryMeta[key].kind == aekGlyph

    ctx.markGeneratedEntry(key)
    clearImage(id)
    ctx.drainImages()
    check key in ctx.entries
    check ctx.atlasEntryMeta[key].kind == aekGenerated

    ctx.markImageEntry(id)
    clearImage(id)
    ctx.drainImages()
    check key notin ctx.entries
    check key notin ctx.atlasEntryMeta

  test "targeted glyph clears remove only matching glyph entries":
    let
      fontA = FontId(Hash(301))
      fontB = FontId(Hash(302))
      typefaceA = TypefaceId(Hash(401))
      typefaceB = TypefaceId(Hash(402))
      glyphFontA = Hash(501)
      glyphFontB = Hash(502)
      glyphTypefaceA = Hash(503)
      generated = Hash(504)
      imageId = ImageId(Hash(505))
      ctx = newTestContext()

    for key in [glyphFontA, glyphFontB, glyphTypefaceA, generated, imageId.Hash]:
      ctx.entries[key] = rect(0, 0, 1, 1)
    ctx.markGlyphEntry(glyphFontA, fontA, typefaceA)
    ctx.markGlyphEntry(glyphFontB, fontB, typefaceB)
    ctx.markGlyphEntry(glyphTypefaceA, fontB, typefaceA)
    ctx.markGeneratedEntry(generated)
    ctx.markImageEntry(imageId)

    clearFontGlyphs(fontA)
    ctx.drainImages()
    check glyphFontA notin ctx.entries
    check glyphFontB in ctx.entries
    check glyphTypefaceA in ctx.entries
    check generated in ctx.entries
    check imageId.Hash in ctx.entries

    clearTypefaceGlyphs(typefaceA)
    ctx.drainImages()
    check glyphTypefaceA notin ctx.entries
    check glyphFontB in ctx.entries
    check generated in ctx.entries
    check imageId.Hash in ctx.entries

  test "clearImageCache clears logical cache backend entries and stale uploads":
    let
      loadedId = imgId("tests/timage_loading/cache-reset/loaded")
      staleId = imgId("tests/timage_loading/cache-reset/stale")
      ctx = newTestContext()
    clearImageCache()
    ctx.drainImages()
    ctx.resetCount = 0

    loadImage(loadedId, newImage(1, 1))
    ctx.drainImages()
    check hasImage(loadedId)
    check loadedId.Hash in ctx.entries

    loadImage(staleId, newImage(1, 1))
    check hasImage(staleId)
    clearImageCache()
    check not hasImage(loadedId)
    check not hasImage(staleId)
    ctx.drainImages()

    check ctx.resetCount == 1
    check ctx.uploaded == @[loadedId]
    check ctx.entries.len == 0

    loadImage(loadedId, newImage(1, 1))
    ctx.drainImages()
    check hasImage(loadedId)
    check ctx.uploaded == @[loadedId, loadedId]
    check loadedId.Hash in ctx.entries

  test "ImageRef retain copy move and final release send owner messages":
    let id = imgId("tests/timage_loading/image-ref-hooks")
    var owned = imageRef(id)
    let retain = recvImageMsg(ImkRetainImage)
    check retain.id == id

    var copied = owned
    var msg: ImageMsg
    check not tryRecvImageMsg(msg)

    owned = owned
    check not tryRecvImageMsg(msg)

    var moved = move(copied)
    copied = ImageRef()
    check not tryRecvImageMsg(msg)

    owned = ImageRef()
    check not tryRecvImageMsg(msg)

    moved = ImageRef()
    let release = recvImageMsg(ImkReleaseImage)
    check release.id == id
    check release.ownerToken == retain.ownerToken

  test "ImageRef release waits for all owner tokens before evicting":
    let
      id = imgId("tests/timage_loading/image-ref-thread")
      ctx = newTestContext()

    clearImage(id)
    ctx.drainImages()

    loadImage(id, newImage(1, 1))
    var mainOwner = imageRef(id)
    var worker: Thread[ImageId]
    createThread(worker, retainImageOnThread, id)
    joinThread(worker)

    ctx.drainImages()
    check id.Hash in ctx.entries
    check hasImage(id)

    mainOwner = ImageRef()
    ctx.drainImages()
    check id.Hash notin ctx.entries
    check not hasImage(id)

  test "manual clear removes retained image immediately":
    let
      id = imgId("tests/timage_loading/image-ref-manual-clear")
      ctx = newTestContext()

    clearImage(id)
    ctx.drainImages()

    var owner = imageRef(id, newImage(1, 1))
    ctx.drainImages()
    check id.Hash in ctx.entries
    check hasImage(id)

    clearImage(id)
    ctx.drainImages()
    check id.Hash notin ctx.entries
    check not hasImage(id)

    owner = ImageRef()
    ctx.drainImages()

  test "FontRef final release clears matching glyph entries":
    setFigDataDir(getCurrentDir() / "data")
    let
      typefaceId = loadTypeface("Ubuntu.ttf")
      uiFont = FigFont(typefaceId: typefaceId, size: 18.0'f32)
      ctx = newTestContext()
    var owner = fontRef(uiFont)
    let glyphImageId = imgId("tests/timage_loading/font-ref-glyph")
    loadGlyphImage(glyphImageId, owner.fontId, typefaceId, newImage(1, 1))

    ctx.drainImages()
    check hasImage(glyphImageId)
    check glyphImageId.Hash in ctx.entries

    owner = FontRef()
    ctx.drainImages()
    check not hasImage(glyphImageId)
    check glyphImageId.Hash notin ctx.entries
