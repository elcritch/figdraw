import std/[hashes, os, tables, unittest]

import pkg/pixie as pixie except readImage

import figdraw/commons
import figdraw/figrender
import figdraw/fignodes

type TestContext = ref object of BackendContext
  entries: Table[Hash, Rect]
  uploaded: seq[ImageId]
  removed: seq[ImageId]
  resetCount: int

method entriesPtr*(ctx: TestContext): ptr Table[Hash, Rect] =
  ctx.entries.addr

method putImage*(ctx: TestContext, imgObj: ImgObj) =
  ctx.uploaded.add(imgObj.id)
  ctx.entries[imgObj.id.Hash] = rect(0, 0, 1, 1)

method removeImage*(ctx: TestContext, id: ImageId) =
  ctx.removed.add(id)
  ctx.entries.del(id.Hash)

method clearImageAtlas*(ctx: TestContext) =
  inc ctx.resetCount
  ctx.entries.clear()

proc newRenders(): Renders =
  Renders(layers: initOrderedTable[ZLevel, RenderList]())

proc drainImages(ctx: TestContext) =
  var renders = newRenders()
  ctx.renderRoot(renders)

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
    let ctx = TestContext(entries: initTable[Hash, Rect]())
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
    let ctx = TestContext(entries: initTable[Hash, Rect]())
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
      ctx = TestContext(entries: initTable[Hash, Rect]())
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
      ctx = TestContext(entries: initTable[Hash, Rect]())
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

  test "clearImageCache clears logical cache backend entries and stale uploads":
    let
      loadedId = imgId("tests/timage_loading/cache-reset/loaded")
      staleId = imgId("tests/timage_loading/cache-reset/stale")
      ctx = TestContext(entries: initTable[Hash, Rect]())
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
