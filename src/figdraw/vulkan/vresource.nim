type VResource*[T] = object
  value*: T
  initialized*: bool

proc `=copy`*[T](
    dest: var VResource[T], src: VResource[T]
) {.error: "VResource is move-only; use sink parameters, reset(), or release().".} =
  discard

proc `=wasMoved`*[T](res: var VResource[T]) =
  res.value = default(T)
  res.initialized = false

proc initVResource*[T](value: sink T): VResource[T] =
  result.value = value
  result.initialized = true

proc isInitialized*[T](res: VResource[T]): bool {.inline.} =
  res.initialized

template `[]`*[T](res: VResource[T]): untyped =
  res.value

proc release*[T](res: var VResource[T]): T =
  result = move(res.value)
  res.initialized = false

proc reset*[T](res: var VResource[T]) =
  if not res.initialized:
    return

  mixin `=destroy`

  var value = move(res.value)
  res.initialized = false
  `=destroy`(value)

proc reset*[T](res: var VResource[T], value: sink T) =
  res.reset()
  res.value = value
  res.initialized = true

proc `=destroy`*[T](res: var VResource[T]) =
  res.reset()
