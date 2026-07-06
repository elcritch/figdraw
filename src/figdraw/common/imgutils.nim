import std/[os, tables, strutils, sets, hashes]
import std/[isolation, locks, times]

import pkg/pixie
import chronicles

import ./rchannels
import ./formatflippy
import ./fonttypes
import ./shared

type
  ImageId* = distinct Hash
  ImgKind* = enum
    FlippyImg
    PixieImg

  ImgObj* = object
    id*: ImageId
    case kind*: ImgKind
    of FlippyImg:
      flippy*: Flippy
    of PixieImg:
      pimg*: Image

  ImageMsgKind* = enum
    ImkPutFlippy
    ImkPutPixie
    ImkPutGlyphPixie
    ImkClearImage
    ImkClearImages
    ImkClearImageCache
    ImkClearFontGlyphs
    ImkClearTypefaceGlyphs

  ImageMsg* = object
    id*: ImageId
    generation*: uint64
    cacheGeneration*: uint64
    fontId*: FontId
    typefaceId*: TypefaceId
    ids*: seq[ImageId]
    case kind*: ImageMsgKind
    of ImkPutFlippy:
      flippy*: Flippy
    of ImkPutPixie, ImkPutGlyphPixie:
      pimg*: Image
    of ImkClearImage, ImkClearImages, ImkClearImageCache, ImkClearFontGlyphs,
        ImkClearTypefaceGlyphs:
      discard

  ImageCacheKind = enum
    ickImage
    ickGlyph

  ImageCacheMeta = object
    kind: ImageCacheKind
    fontId: FontId
    typefaceId: TypefaceId

var
  imageChan* = newRChan[ImgObj](1000)
  imageMsgChan = newRChan[ImageMsg](1000)
  imageCached*: HashSet[ImageId]
  imageGenerations: Table[ImageId, uint64]
  imageCacheMeta: Table[ImageId, ImageCacheMeta]
  imageCacheGeneration: uint64
  imageMsgOrderLock: Lock
  imageCachedLock*: Lock

imageMsgOrderLock.initLock()
imageCachedLock.initLock()

proc `==`*(a, b: ImageId): bool {.borrow.}

proc imgId*(name: string): ImageId =
  hash(name).ImageId

proc logImage(file: string) =
  trace "load image file", flippyPath = file

proc resolveAssetPath(filePath: string): string =
  if filePath.len == 0:
    return ""
  if fileExists(filePath):
    return filePath
  let dataPath = figDataDir() / filePath
  if fileExists(dataPath):
    return dataPath
  return filePath

proc readImage*(filePath: string): Flippy =
  # Need to load imagePath, check to see if the .flippy file is around
  let resolvedPath = resolveAssetPath(filePath)
  logImage(resolvedPath)
  if not fileExists(resolvedPath):
    return Flippy()

  if resolvedPath.endsWith(".flippy"):
    return loadFlippy(resolvedPath)

  let flippyFilePath = resolvedPath.changeFileExt(".flippy")
  if not fileExists(flippyFilePath):
    # No Flippy file generate new one
    pngToFlippy(resolvedPath, flippyFilePath)
  else:
    let
      mtFlippy = getLastModificationTime(flippyFilePath).toUnix
      mtImage = getLastModificationTime(resolvedPath).toUnix
    if mtFlippy < mtImage:
      # Flippy file too old, regenerate
      pngToFlippy(resolvedPath, flippyFilePath)
  result = loadFlippy(flippyFilePath)

proc toImgObj*(image: Flippy): ImgObj =
  result = ImgObj(kind: FlippyImg, flippy: image)

proc toImgObj*(image: Image): ImgObj =
  result = ImgObj(kind: PixieImg, pimg: image)

proc imageGenerationLocked(id: ImageId): uint64 =
  imageGenerations.getOrDefault(id, 0'u64)

proc bumpImageGenerationLocked(id: ImageId): uint64 =
  result = imageGenerationLocked(id) + 1'u64
  imageGenerations[id] = result

proc markImageCachedLocked(id: ImageId) =
  imageCached.incl(id)
  imageCacheMeta[id] = ImageCacheMeta(kind: ickImage)

proc markGlyphCachedLocked(id: ImageId, fontId: FontId, typefaceId: TypefaceId) =
  imageCached.incl(id)
  imageCacheMeta[id] =
    ImageCacheMeta(kind: ickGlyph, fontId: fontId, typefaceId: typefaceId)

proc clearCachedImageLocked(id: ImageId) =
  imageCached.excl(id)
  imageCacheMeta.del(id)
  discard bumpImageGenerationLocked(id)

proc clearCachedGlyphsLocked(fontId: FontId): seq[ImageId] =
  for id, meta in imageCacheMeta.pairs:
    if meta.kind == ickGlyph and meta.fontId == fontId:
      result.add(id)
  for id in result:
    clearCachedImageLocked(id)

proc clearCachedTypefaceGlyphsLocked(typefaceId: TypefaceId): seq[ImageId] =
  for id, meta in imageCacheMeta.pairs:
    if meta.kind == ickGlyph and meta.typefaceId == typefaceId:
      result.add(id)
  for id in result:
    clearCachedImageLocked(id)

proc hasImage*(id: ImageId): bool =
  withLock imageCachedLock:
    result = id in imageCached

proc imageMessageCurrent*(msg: ImageMsg): bool =
  withLock imageCachedLock:
    result =
      msg.cacheGeneration == imageCacheGeneration and
      msg.generation == imageGenerationLocked(msg.id)

proc tryRecvImageMsg*(msg: var ImageMsg): bool =
  imageMsgChan.tryRecv(msg)

proc toImageMsg(
    imgObj: var ImgObj, generation: uint64, cacheGeneration: uint64
): ImageMsg =
  case imgObj.kind
  of FlippyImg:
    result = ImageMsg(
      kind: ImkPutFlippy,
      id: imgObj.id,
      generation: generation,
      cacheGeneration: cacheGeneration,
      flippy: move(imgObj.flippy),
    )
  of PixieImg:
    result = ImageMsg(
      kind: ImkPutPixie,
      id: imgObj.id,
      generation: generation,
      cacheGeneration: cacheGeneration,
      pimg: imgObj.pimg,
    )

proc sendImage*(imgObj: var ImgObj) =
  var generation: uint64
  var cacheGeneration: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      markImageCachedLocked(imgObj.id)
      generation = imageGenerationLocked(imgObj.id)
      cacheGeneration = imageCacheGeneration
    var msg = imgObj.toImageMsg(generation, cacheGeneration)
    imageMsgChan.send(unsafeIsolate msg)

proc sendImageCached*(imgObj: var ImgObj) =
  var cached = false
  var generation: uint64
  var cacheGeneration: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      if imgObj.id in imageCached:
        cached = true
      else:
        markImageCachedLocked(imgObj.id)
        generation = imageGenerationLocked(imgObj.id)
        cacheGeneration = imageCacheGeneration
    if not cached:
      var msg = imgObj.toImageMsg(generation, cacheGeneration)
      imageMsgChan.send(unsafeIsolate msg)

proc loadGlyphImage*(
    id: ImageId, fontId: FontId, typefaceId: TypefaceId, image: Image
) =
  var generation: uint64
  var cacheGeneration: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      markGlyphCachedLocked(id, fontId, typefaceId)
      generation = imageGenerationLocked(id)
      cacheGeneration = imageCacheGeneration
    var msg = ImageMsg(
      kind: ImkPutGlyphPixie,
      id: id,
      generation: generation,
      cacheGeneration: cacheGeneration,
      fontId: fontId,
      typefaceId: typefaceId,
      pimg: image,
    )
    imageMsgChan.send(unsafeIsolate msg)

proc clearImage*(id: ImageId) =
  var generation: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      imageCacheMeta.del(id)
      imageCached.excl(id)
      generation = bumpImageGenerationLocked(id)
    var msg = ImageMsg(kind: ImkClearImage, id: id, generation: generation)
    imageMsgChan.send(unsafeIsolate msg)

proc clearImages*(ids: openArray[ImageId]) =
  if ids.len == 0:
    return
  var msg = ImageMsg(kind: ImkClearImages)
  for id in ids:
    msg.ids.add(id)
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      for id in ids:
        clearCachedImageLocked(id)
    imageMsgChan.send(unsafeIsolate msg)

proc clearImageCache*() =
  var cacheGeneration: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      imageCached.clear()
      imageGenerations.clear()
      imageCacheMeta.clear()
      imageCacheGeneration.inc()
      cacheGeneration = imageCacheGeneration
    var msg = ImageMsg(kind: ImkClearImageCache, cacheGeneration: cacheGeneration)
    imageMsgChan.send(unsafeIsolate msg)

proc clearFontGlyphs*(fontId: FontId) =
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      discard clearCachedGlyphsLocked(fontId)
    var msg = ImageMsg(kind: ImkClearFontGlyphs, fontId: fontId)
    imageMsgChan.send(unsafeIsolate msg)

proc clearTypefaceGlyphs*(typefaceId: TypefaceId) =
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      discard clearCachedTypefaceGlyphsLocked(typefaceId)
    var msg = ImageMsg(kind: ImkClearTypefaceGlyphs, typefaceId: typefaceId)
    imageMsgChan.send(unsafeIsolate msg)

proc loadImage*(filePath: string): ImageId =
  var flippy = readImage(filePath)
  result = imgId(filePath)
  var imgObj = ImgObj(id: result, kind: FlippyImg, flippy: ensureMove flippy)
  sendImageCached(imgObj)

proc loadImage*(id: ImageId, image: Image) =
  var imgObj = ImgObj(id: id, kind: PixieImg, pimg: image)
  sendImage(imgObj)
