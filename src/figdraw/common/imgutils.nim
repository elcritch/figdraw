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
  OwnerToken* = distinct uint64
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
    ImkRetainImage
    ImkReleaseImage
    ImkRetainFont
    ImkReleaseFont

  ImageMsg* = object
    id*: ImageId
    generation*: uint64
    cacheGeneration*: uint64
    fontId*: FontId
    typefaceId*: TypefaceId
    ownerToken*: OwnerToken
    ids*: seq[ImageId]
    case kind*: ImageMsgKind
    of ImkPutFlippy:
      flippy*: Flippy
    of ImkPutPixie, ImkPutGlyphPixie:
      pimg*: Image
    of ImkClearImage, ImkClearImages, ImkClearImageCache, ImkClearFontGlyphs,
        ImkClearTypefaceGlyphs, ImkRetainImage, ImkReleaseImage, ImkRetainFont,
        ImkReleaseFont:
      discard

  ImageRefHandle = object
    imageId: ImageId

  ## Thread-affine managed image handle.
  ##
  ## Pass raw ImageId values across threads and create a new ImageRef on the
  ## receiving thread when that thread needs ownership.
  ImageRef* = ref ImageRefHandle

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
  ownerTokenLock: Lock
  nextOwnerToken: uint64
  localOwnerToken {.threadvar.}: OwnerToken
  localImageRefCounts {.threadvar.}: Table[ImageId, int]
  localFontRefCounts {.threadvar.}: Table[FontId, int]

imageMsgOrderLock.initLock()
imageCachedLock.initLock()
ownerTokenLock.initLock()

proc `==`*(a, b: ImageId): bool {.borrow.}
proc `==`*(a, b: OwnerToken): bool {.borrow.}
proc hash*(token: OwnerToken): Hash {.borrow.}

proc currentOwnerToken*(): OwnerToken =
  if localOwnerToken == OwnerToken(0):
    withLock ownerTokenLock:
      inc nextOwnerToken
      localOwnerToken = OwnerToken(nextOwnerToken)
  localOwnerToken

proc sendRetainImage(id: ImageId, ownerToken: OwnerToken) =
  withLock imageMsgOrderLock:
    var msg = ImageMsg(kind: ImkRetainImage, id: id, ownerToken: ownerToken)
    imageMsgChan.send(unsafeIsolate msg)

proc sendReleaseImage(id: ImageId, ownerToken: OwnerToken) =
  withLock imageMsgOrderLock:
    var msg = ImageMsg(kind: ImkReleaseImage, id: id, ownerToken: ownerToken)
    imageMsgChan.send(unsafeIsolate msg)

proc sendRetainFont(fontId: FontId, ownerToken: OwnerToken) =
  withLock imageMsgOrderLock:
    var msg = ImageMsg(kind: ImkRetainFont, fontId: fontId, ownerToken: ownerToken)
    imageMsgChan.send(unsafeIsolate msg)

proc sendReleaseFont(fontId: FontId, ownerToken: OwnerToken) =
  withLock imageMsgOrderLock:
    var msg = ImageMsg(kind: ImkReleaseFont, fontId: fontId, ownerToken: ownerToken)
    imageMsgChan.send(unsafeIsolate msg)

proc retainImageRefId*(id: ImageId) =
  let ownerToken = currentOwnerToken()
  let count = localImageRefCounts.getOrDefault(id, 0)
  localImageRefCounts[id] = count + 1
  if count == 0:
    sendRetainImage(id, ownerToken)

proc releaseImageRefId*(id: ImageId) =
  let count = localImageRefCounts.getOrDefault(id, 0)
  if count > 1:
    localImageRefCounts[id] = count - 1
  elif count == 1:
    localImageRefCounts.del(id)
    sendReleaseImage(id, currentOwnerToken())

proc retainFontRefId*(fontId: FontId) =
  let ownerToken = currentOwnerToken()
  let count = localFontRefCounts.getOrDefault(fontId, 0)
  localFontRefCounts[fontId] = count + 1
  if count == 0:
    sendRetainFont(fontId, ownerToken)

proc releaseFontRefId*(fontId: FontId) =
  let count = localFontRefCounts.getOrDefault(fontId, 0)
  if count > 1:
    localFontRefCounts[fontId] = count - 1
  elif count == 1:
    localFontRefCounts.del(fontId)
    sendReleaseFont(fontId, currentOwnerToken())

proc `=destroy`(imageRef: ImageRefHandle) =
  releaseImageRefId(imageRef.imageId)

func id*(imageRef: ImageRef): ImageId {.inline.} =
  ## The image ID owned by this handle.
  imageRef.imageId

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

proc forgetReleasedImage*(id: ImageId) =
  withLock imageCachedLock:
    clearCachedImageLocked(id)

proc forgetReleasedFontGlyphs*(fontId: FontId) =
  withLock imageCachedLock:
    discard clearCachedGlyphsLocked(fontId)

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

proc clearImage*(image: ImageRef) =
  clearImage(image.id)

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

proc clearImages*(images: openArray[ImageRef]) =
  if images.len == 0:
    return
  var ids = newSeqOfCap[ImageId](images.len)
  for image in images:
    ids.add(image.id)
  clearImages(ids)

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

proc imageRef*(id: ImageId): ImageRef =
  ## Retain an existing image ID for the current thread.
  retainImageRefId(id)
  new result
  result.imageId = id

proc loadImageRef*(filePath: string): ImageRef =
  ## Load an image through the normal cache path and retain its ID.
  imageRef(loadImage(filePath))

proc imageRef*(id: ImageId, image: Image): ImageRef =
  ## Upload an image through the normal message path and retain its ID.
  loadImage(id, image)
  imageRef(id)
