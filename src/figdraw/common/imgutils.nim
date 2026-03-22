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

var
  imageChan* = newRChan[ImgObj](1000)
  imageCached*: HashSet[ImageId]
  glyphImageIdsByFont*: Table[FontId, HashSet[ImageId]]
  imageCachedLock*: Lock

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

proc hasImage*(id: ImageId): bool =
  withLock imageCachedLock:
    result = id in imageCached

proc sendImage*(imgObj: var ImgObj) =
  withLock imageCachedLock:
    imageCached.incl(imgObj.id)
  imageChan.send(unsafeIsolate imgObj)

proc sendImageCached*(imgObj: var ImgObj) =
  var cached = false
  withLock imageCachedLock:
    if imgObj.id in imageCached:
      cached = true
    else:
      imageCached.incl(imgObj.id)
  if not cached:
    imageChan.send(unsafeIsolate imgObj)

proc loadImage*(filePath: string): ImageId =
  var flippy = readImage(filePath)
  result = imgId(filePath)
  var imgObj = ImgObj(id: result, kind: FlippyImg, flippy: ensureMove flippy)
  sendImageCached(imgObj)

proc loadImage*(id: ImageId, image: Image) =
  var imgObj = ImgObj(id: id, kind: PixieImg, pimg: image)
  sendImage(imgObj)

proc trackGlyphImage*(fontId: FontId, imageId: ImageId) =
  withLock imageCachedLock:
    if fontId notin glyphImageIdsByFont:
      glyphImageIdsByFont[fontId] = initHashSet[ImageId]()
    glyphImageIdsByFont[fontId].incl(imageId)

proc clearGlyphImagesForFonts*(fontIds: openArray[FontId]): seq[ImageId] =
  var deduped = initHashSet[ImageId]()
  withLock imageCachedLock:
    for fontId in fontIds:
      if fontId notin glyphImageIdsByFont:
        continue
      for imageId in glyphImageIdsByFont[fontId]:
        imageCached.excl(imageId)
        if imageId notin deduped:
          deduped.incl(imageId)
          result.add(imageId)
      glyphImageIdsByFont.del(fontId)

proc clearGlyphImagesForAllFonts*(): seq[ImageId] =
  var deduped = initHashSet[ImageId]()
  withLock imageCachedLock:
    for _, imageIds in glyphImageIdsByFont.pairs():
      for imageId in imageIds:
        imageCached.excl(imageId)
        if imageId notin deduped:
          deduped.incl(imageId)
          result.add(imageId)
    glyphImageIdsByFont.clear()
