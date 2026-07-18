import std/[hashes, os, tables, unittest]

import pkg/pixie as pixie except readImage

import figdraw/commons
import figdraw/common/typefaces
import figdraw/figrender
import figdraw/fignodes

type TestContext = ref object of BackendContext
  entries: Table[Hash, Rect]
  atlasEntryMeta: Table[Hash, AtlasEntryMeta]
  atlasSize: int
  packedArea: int
  uploaded: seq[ImageId]
  updated: seq[ImageId]
  pixels: Table[ImageId, Image]
  removed: seq[ImageId]
  drawn: seq[Hash]
  resetCount: int

method entriesPtr*(ctx: TestContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method atlasEntryMetaPtr*(ctx: TestContext): var Table[Hash, AtlasEntryMeta] =
  result = ctx.atlasEntryMeta

method atlasSize*(ctx: TestContext): int =
  ctx.atlasSize

method atlasPackedArea*(ctx: TestContext): int =
  ctx.packedArea

method putImage*(ctx: TestContext, imgObj: ImgObj) =
  ctx.uploaded.add(imgObj.id)
  case imgObj.kind
  of FlippyImg:
    let mip = imgObj.flippy.mipmaps[0]
    ctx.entries[imgObj.id.Hash] = rect(
      0,
      0,
      mip.width.float32 / ctx.atlasSize.float32,
      mip.height.float32 / ctx.atlasSize.float32,
    )
  of PixieImg:
    ctx.entries[imgObj.id.Hash] = rect(
      0,
      0,
      imgObj.pimg.width.float32 / ctx.atlasSize.float32,
      imgObj.pimg.height.float32 / ctx.atlasSize.float32,
    )
    ctx.pixels[imgObj.id] = imgObj.pimg.copy()

method putImage*(ctx: TestContext, path: Hash, image: Image) =
  let id = ImageId(path)
  ctx.uploaded.add(id)
  ctx.entries[path] = rect(
    0,
    0,
    image.width.float32 / ctx.atlasSize.float32,
    image.height.float32 / ctx.atlasSize.float32,
  )
  ctx.pixels[id] = image.copy()

method updateImage*(ctx: TestContext, path: Hash, image: Image) =
  let id = ImageId(path)
  ctx.updated.add(id)
  ctx.pixels[id] = image.copy()

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
  ctx.noteAtlasRebuilt()

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
  result = TestContext(
    entries: initTable[Hash, Rect](),
    atlasEntryMeta: initTable[Hash, AtlasEntryMeta](),
    pixels: initTable[ImageId, Image](),
    atlasSize: 16,
  )
  result.ensureImageMessageSubscription()

proc newRenders(): Renders =
  Renders(layers: initOrderedTable[ZLevel, RenderList]())

proc drainImages(ctx: TestContext) =
  var renders = newRenders()
  ctx.renderRoot(renders)

proc recvImageMsg(kind: ImageMsgKind): ImageMsg =
  require tryRecvImageMsg(result)
  check result.kind == kind

proc recvImageMsg(
    subscription: ImageMessageSubscription, kind: ImageMsgKind
): ImageMsg =
  require subscription.tryRecvImageMsg(result)
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
    ctx.uploaded.setLen(0)

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

  test "replaceImage updates a same-size atlas slot in place":
    let
      id = imgId("tests/timage_loading/replace/same-size")
      ctx = newTestContext()
      initial = newImage(2, 3)
      replacement = newImage(2, 3)
    initial.fill(rgba(10, 20, 30, 255))
    replacement.fill(rgba(40, 50, 60, 255))
    clearImageCache()
    ctx.drainImages()

    loadImage(id, initial)
    ctx.drainImages()
    let initialRect = ctx.entries[id.Hash]

    replaceImage(id, replacement)
    ctx.drainImages()

    check ctx.uploaded == @[id]
    check ctx.updated == @[id]
    check ctx.entries[id.Hash] == initialRect
    check ctx.pixels[id][0, 0] == rgba(40, 50, 60, 255)
    clearImage(id)
    ctx.drainImages()

  test "replaceImage reallocates when dimensions change":
    let
      id = imgId("tests/timage_loading/replace/different-size")
      ctx = newTestContext()
      replacement = newImage(4, 1)
    replacement.fill(rgba(70, 80, 90, 255))
    clearImageCache()
    ctx.drainImages()

    loadImage(id, newImage(2, 3))
    ctx.drainImages()
    replaceImage(id, replacement)
    ctx.drainImages()

    check ctx.uploaded == @[id, id]
    check ctx.updated.len == 0
    check ctx.entries[id.Hash].w == 4.0'f32 / ctx.atlasSize.float32
    check ctx.entries[id.Hash].h == 1.0'f32 / ctx.atlasSize.float32
    check ctx.pixels[id][0, 0] == rgba(70, 80, 90, 255)
    clearImage(id)
    ctx.drainImages()

  test "replaceImage keeps only the newest queued frame and replay value":
    let
      id = imgId("tests/timage_loading/replace/newest")
      ctx = newTestContext()
      firstFrame = newImage(2, 2)
      newestFrame = newImage(3, 1)
    firstFrame.fill(rgba(100, 110, 120, 255))
    newestFrame.fill(rgba(130, 140, 150, 255))
    clearImageCache()
    ctx.drainImages()

    replaceImage(id, firstFrame)
    replaceImage(id, newestFrame)
    ctx.drainImages()

    check hasImage(id)
    check ctx.uploaded == @[id]
    check ctx.updated.len == 0
    check ctx.pixels[id].width == 3
    check ctx.pixels[id].height == 1
    check ctx.pixels[id][0, 0] == rgba(130, 140, 150, 255)

    let late = newTestContext()
    late.drainImages()
    check late.uploaded == @[id]
    check late.pixels[id].width == 3
    check late.pixels[id].height == 1
    check late.pixels[id][0, 0] == rgba(130, 140, 150, 255)

    clearImage(id)
    ctx.drainImages()
    late.drainImages()

  test "replaceImage replays the newest frame after an atlas rebuild":
    let
      id = imgId("tests/timage_loading/replace/rebuild")
      ctx = newTestContext()
      replacement = newImage(3, 2)
    replacement.fill(rgba(160, 170, 180, 255))
    clearImageCache()
    ctx.drainImages()

    replaceImage(id, replacement)
    ctx.drainImages()
    check ctx.uploaded == @[id]

    ctx.clearImageAtlas()
    check id.Hash notin ctx.entries
    ctx.drainImages()

    check ctx.uploaded == @[id, id]
    check id.Hash in ctx.entries
    check ctx.pixels[id].width == 3
    check ctx.pixels[id].height == 2
    check ctx.pixels[id][0, 0] == rgba(160, 170, 180, 255)

    clearImage(id)
    ctx.drainImages()

  test "loadImage path after clear uploads the current image":
    setFigDataDir(getCurrentDir() / "data")
    let
      path = "arrow.png"
      id = imgId(path)
      ctx = newTestContext()
    clearImage(id)
    ctx.drainImages()
    ctx.uploaded.setLen(0)

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

  test "atlasUsage reports live entries and packer usage":
    let
      imageId = imgId("tests/timage_loading/atlas-usage/image")
      glyphKey = Hash(601)
      generatedKey = Hash(602)
      unknownKey = Hash(603)
      fontId = FontId(Hash(604))
      typefaceId = TypefaceId(Hash(605))
      ctx = newTestContext()
    ctx.packedArea = 96
    ctx.entries[imageId.Hash] = rect(0, 0, 0.25, 0.5)
    ctx.entries[glyphKey] = rect(0.25, 0, 0.25, 0.25)
    ctx.entries[generatedKey] = rect(0.5, 0, 0.125, 0.125)
    ctx.entries[unknownKey] = rect(0.625, 0, 0.0625, 0.0625)
    ctx.markImageEntry(imageId)
    ctx.markGlyphEntry(glyphKey, fontId, typefaceId)
    ctx.markGeneratedEntry(generatedKey)

    let usage = ctx.atlasUsage()
    check usage.atlasSize == 16
    check usage.atlasArea == 256
    check usage.usedArea == 53
    check usage.packedArea == 96
    check usage.entryCount == 4
    check usage.imageCount == 1
    check usage.glyphCount == 1
    check usage.generatedCount == 1
    check usage.unknownCount == 1
    check usage.usedRatio() == 53.0'f32 / 256.0'f32
    check usage.packedRatio() == 96.0'f32 / 256.0'f32

  test "publishAtlasUsage updates cross-thread snapshot":
    let
      imageId = imgId("tests/timage_loading/atlas-usage/snapshot")
      ctx = newTestContext()
      before = atlasUsageSnapshot()
    ctx.packedArea = 128
    ctx.entries[imageId.Hash] = rect(0, 0, 0.5, 0.5)
    ctx.markImageEntry(imageId)

    ctx.publishAtlasUsage()
    let usage = atlasUsageSnapshot()
    check usage.snapshotId > before.snapshotId
    check usage.atlasSize == 16
    check usage.usedArea == 64
    check usage.packedArea == 128
    check usage.entryCount == 1
    check usage.imageCount == 1

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
    ctx.uploaded.setLen(0)

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

  test "image uploads and final releases reach every renderer":
    let
      id = imgId("tests/timage_loading/broadcast")
      first = newTestContext()
      second = newTestContext()
    clearImage(id)
    first.drainImages()
    second.drainImages()

    var owned = imageRef(id)
    let retain = recvImageMsg(ImkRetainImage)
    check retain.id == id
    loadImage(id, newImage(2, 2))
    first.drainImages()
    second.drainImages()
    check id.Hash in first.entries
    check id.Hash in second.entries

    owned = nil
    let release = recvImageMsg(ImkReleaseImage)
    check release.id == id
    first.drainImages()
    second.drainImages()
    check id.Hash notin first.entries
    check id.Hash notin second.entries

  test "renderers created after an upload replay the current image cache":
    let id = imgId("tests/timage_loading/late-renderer")
    clearImage(id)
    loadImage(id, newImage(2, 2))

    let late = newTestContext()
    late.drainImages()
    check id.Hash in late.entries
    check id in late.uploaded

    clearImage(id)
    late.drainImages()
    check id.Hash notin late.entries

  test "renderer messages and replay own independent image data":
    clearImageCache()
    let
      id = imgId("tests/timage_loading/independent-replay")
      first = newImageMessageSubscription()
      second = newImageMessageSubscription()
      image = newImage(1, 1)
    image[0, 0] = rgba(10, 20, 30, 255)
    loadImage(id, image)

    var
      firstMsg = first.recvImageMsg(ImkPutPixie)
      secondMsg = second.recvImageMsg(ImkPutPixie)
    firstMsg.pimg[0, 0] = rgba(100, 110, 120, 255)
    check secondMsg.pimg[0, 0] == rgba(10, 20, 30, 255)

    let late = newImageMessageSubscription()
    var replay = late.recvImageMsg(ImkPutPixie)
    check replay.pimg[0, 0] == rgba(10, 20, 30, 255)
    secondMsg.pimg[0, 0] = rgba(200, 210, 220, 255)
    check replay.pimg[0, 0] == rgba(10, 20, 30, 255)

    clearImage(id)

  test "a full renderer subscription does not block resource publishers":
    clearImageCache()
    let subscription = newImageMessageSubscription()
    for i in 1 .. 5000:
      retainFontRefId(FontId(Hash(i)))

    var msg: ImageMsg
    check subscription.tryRecvImageMsg(msg)

    for i in 1 .. 5000:
      releaseFontRefId(FontId(Hash(i)))
    while tryRecvImageMsg(msg):
      discard

  test "atlas generations are renderer-local and advance on rebuild":
    let
      first = newTestContext()
      second = newTestContext()
      firstGeneration = first.atlasGeneration()
      secondGeneration = second.atlasGeneration()

    first.clearImageAtlas()
    check first.atlasGeneration() != firstGeneration
    check second.atlasGeneration() == secondGeneration
    check first.atlasRebuildCount() > second.atlasRebuildCount()

  test "ImageRef copies share one retained handle":
    let id = imgId("tests/timage_loading/image-ref-hooks")
    var owned = imageRef(id)
    let retain = recvImageMsg(ImkRetainImage)
    check retain.id == id

    var copied = owned
    check copied == owned
    var msg: ImageMsg
    check not tryRecvImageMsg(msg)

    owned = owned
    check not tryRecvImageMsg(msg)

    var moved = move(copied)
    check copied.isNil
    check not tryRecvImageMsg(msg)

    owned = nil
    check not tryRecvImageMsg(msg)

    moved = nil
    let release = recvImageMsg(ImkReleaseImage)
    check release.id == id
    check release.ownerToken == retain.ownerToken

  test "ImageRefs for the same ID share backend ownership":
    let id = imgId("tests/timage_loading/image-ref-separate-handles")
    var first = imageRef(id)
    let retain = recvImageMsg(ImkRetainImage)

    var second = imageRef(id)
    var msg: ImageMsg
    check not tryRecvImageMsg(msg)

    first = nil
    check not tryRecvImageMsg(msg)

    second = nil
    let release = recvImageMsg(ImkReleaseImage)
    check release.id == retain.id
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

    mainOwner = nil
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

    owner = nil
    ctx.drainImages()

  test "ImageRef works with imageStyle and manual clear overloads":
    let
      id = imgId("tests/timage_loading/image-ref-style")
      ctx = newTestContext()

    clearImage(id)
    ctx.drainImages()

    var owner = imageRef(id, newImage(1, 1))
    ctx.drainImages()
    let
      defaultStyle = imageStyle(owner)
      tintedStyle = imageStyle(owner, rgba(10, 20, 30, 255))
    check defaultStyle.id == id
    check defaultStyle.fill == fill(rgba(255, 255, 255, 255))
    check tintedStyle.id == id
    check tintedStyle.fill == fill(rgba(10, 20, 30, 255))

    clearImage(owner)
    ctx.drainImages()
    check id.Hash notin ctx.entries
    check not hasImage(id)

    owner = nil
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

    owner = nil
    ctx.drainImages()
    check not hasImage(glyphImageId)
    check glyphImageId.Hash notin ctx.entries
