import darwin/objc/runtime

{.passL: "-lobjc".}

proc objc_autoreleasePoolPush(): pointer {.importc, cdecl.}
proc objc_autoreleasePoolPop(pool: pointer) {.importc, cdecl.}

type AutoreleasePool* = object
  handle: pointer

proc start*(p: var AutoreleasePool) =
  if p.handle != nil:
    return
  p.handle = objc_autoreleasePoolPush()

proc stop*(p: var AutoreleasePool) =
  if p.handle == nil:
    return
  objc_autoreleasePoolPop(p.handle)
  p.handle = nil

proc `=destroy`*(p: var AutoreleasePool) =
  p.stop()

template withAutoreleasePool*(body: untyped) =
  block:
    var pool = AutoreleasePool()
    pool.start()
    body

type ObjcOwned*[T] = object
  p: T

func isNil*[T](o: ObjcOwned[T]): bool =
  cast[pointer](o.p) == nil

func borrow*[T](o: ObjcOwned[T]): T =
  o.p

proc clear*[T](o: var ObjcOwned[T]) =
  if cast[pointer](o.p) != nil:
    release(cast[NSObject](o.p))
    o.p = cast[T](nil)

proc resetRetained*[T](o: var ObjcOwned[T], p: T) =
  ## Sets to an already-retained (+1) ObjC object (e.g. methods starting with `new`,
  ## `alloc/init`, or APIs annotated NS_RETURNS_RETAINED). Releases the previous value.
  if o.p == p:
    return
  o.clear()
  o.p = p

proc resetBorrowed*[T](o: var ObjcOwned[T], p: T) =
  ## Sets to a borrowed (+0/autoreleased) ObjC object by retaining it.
  if o.p == p:
    return
  o.clear()
  o.p =
    (if cast[pointer](p) == nil: cast[T](nil)
    else: cast[T](retain(cast[NSObject](p))))

proc fromRetained*[T](p: T): ObjcOwned[T] =
  ObjcOwned[T](p: p)

proc fromBorrowed*[T](p: T): ObjcOwned[T] =
  ObjcOwned[T](
    p: (
      if cast[pointer](p) == nil: cast[T](nil)
      else: cast[T](retain(cast[NSObject](p)))
    )
  )

proc `=destroy`*[T](o: var ObjcOwned[T]) =
  o.clear()

proc `=copy`*[T](dst: var ObjcOwned[T], src: ObjcOwned[T]) =
  if dst.p == src.p:
    return
  dst.clear()
  dst.p = (
    if cast[pointer](src.p) == nil: cast[T](nil)
    else: cast[T](retain(cast[NSObject](src.p)))
  )

proc `=sink`*[T](dst: var ObjcOwned[T], src: ObjcOwned[T]) =
  dst.clear()
  dst.p = src.p
  # `=sink`'s signature requires an immutable `src`. Null it out through its address
  # so its destructor doesn't `release` the moved pointer.
  cast[ptr ObjcOwned[T]](unsafeAddr src)[].p = cast[T](nil)
