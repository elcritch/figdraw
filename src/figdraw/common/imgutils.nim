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
  imageCachedLock*: Lock

imageCachedLock.initLock()

proc `==`*(a, b: ImageId): bool {.borrow.}

proc imgId*(name: string): ImageId =
  hash(name).ImageId

proc logImage(file: string) =
  debug "load image file", flippyPath = file

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

proc sendImage*(imgObj: var ImgObj) =
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

proc loadImage*(id: ImageId, image: var Image) =
  var imgObj = ImgObj(id: id, kind: PixieImg, pimg: ensureMove image)
  sendImage(imgObj)

