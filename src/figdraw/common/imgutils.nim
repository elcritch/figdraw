import std/[os, unicode, sequtils, tables, strutils, sets, hashes]
import std/[isolation, locks, times]

import pkg/vmath
import pkg/pixie
import pkg/pixie/fonts
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
    ImkClearImage
    ImkClearImages
    ImkClearImageCache

  ImageMsg* = object
    id*: ImageId
    generation*: uint64
    cacheGeneration*: uint64
    ids*: seq[ImageId]
    case kind*: ImageMsgKind
    of ImkPutFlippy:
      flippy*: Flippy
    of ImkPutPixie:
      pimg*: Image
    of ImkClearImage, ImkClearImages, ImkClearImageCache:
      discard

var
  imageChan* = newRChan[ImgObj](1000)
  imageMsgChan = newRChan[ImageMsg](1000)
  imageCached*: HashSet[ImageId]
  imageGenerations: Table[ImageId, uint64]
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
      imageCached.incl(imgObj.id)
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
        imageCached.incl(imgObj.id)
        generation = imageGenerationLocked(imgObj.id)
        cacheGeneration = imageCacheGeneration
    if not cached:
      var msg = imgObj.toImageMsg(generation, cacheGeneration)
      imageMsgChan.send(unsafeIsolate msg)

proc clearImage*(id: ImageId) =
  var generation: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
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
        imageCached.excl(id)
        discard bumpImageGenerationLocked(id)
    imageMsgChan.send(unsafeIsolate msg)

proc clearImageCache*() =
  var cacheGeneration: uint64
  withLock imageMsgOrderLock:
    withLock imageCachedLock:
      imageCached.clear()
      imageGenerations.clear()
      imageCacheGeneration.inc()
      cacheGeneration = imageCacheGeneration
    var msg = ImageMsg(kind: ImkClearImageCache, cacheGeneration: cacheGeneration)
    imageMsgChan.send(unsafeIsolate msg)

proc loadImage*(filePath: string): ImageId =
  var flippy = readImage(filePath)
  result = imgId(filePath)
  var imgObj = ImgObj(id: result, kind: FlippyImg, flippy: ensureMove flippy)
  sendImageCached(imgObj)

proc loadImage*(id: ImageId, image: Image) =
  var imgObj = ImgObj(id: id, kind: PixieImg, pimg: image)
  sendImage(imgObj)
