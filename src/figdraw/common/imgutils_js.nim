import std/hashes

type
  ImageId* = distinct Hash

  ImgObj* = object
    id*: ImageId

  ImageChannel* = object

var imageChan* = ImageChannel()

proc `==`*(a, b: ImageId): bool {.borrow.}

proc imgId*(name: string): ImageId =
  hash(name).ImageId

proc tryRecv*(ch: ImageChannel; msg: var ImgObj): bool =
  false

proc hasImage*(id: ImageId): bool =
  false

proc loadImage*(filePath: string): ImageId =
  imgId(filePath)

proc loadImage*(id: ImageId; image: auto) =
  discard
