type
  RChan*[T] = object

proc newRChan*[T](size: int = 0): RChan[T] =
  RChan[T]()

proc tryRecv*[T](ch: RChan[T], msg: var T): bool =
  false

proc send*[T](ch: var RChan[T], msg: T) =
  discard

proc push*[T](ch: var RChan[T], msg: T) =
  discard
