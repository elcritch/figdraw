## Bounded native-font ownership shared by layout and raster threads.
## RelayFont values retain identity and metrics, never an evictable OS handle.

import std/[locks, math, os, tempfiles]
import ../[fonttypes, typefaces, shared]
from pkg/uirelays/screen as relays import nil

type
  RelayFont* = object
    fontId: FontId
    pixelSize: int
    metrics*: relays.FontMetrics

  CachedFont = object
    fontId: FontId
    typefaceId: TypefaceId
    pixelSize: int
    handle: relays.Font
    metrics: relays.FontMetrics
    path: string
    temporary: bool
    lastUse: uint64

var
  relayLock: Lock
  provider: relays.FontRelays
  cache: seq[CachedFont]
  capacity = 64
  useCounter: uint64

relayLock.initLock()

proc removeTemporary(path: string) =
  try:
    removeFile(path)
  except OSError:
    discard # A failed temporary-file cleanup must not interrupt rendering.

proc closeEntry(index: int) =
  provider.closeFont(cache[index].handle)
  if cache[index].temporary:
    removeTemporary(cache[index].path)
  cache.delete(index)

proc initUirelaysFontProvider*(fonts: relays.FontRelays, maxFonts: Positive = 64) =
  ## Installs a provider while font work is idle. It never changes window relays.
  if fonts.openFont.isNil or fonts.closeFont.isNil or fonts.measureText.isNil or
      fonts.renderText.isNil:
    raise newException(ValueError, "UIRelays requires offscreen font rendering")
  {.cast(gcsafe).}:
    withLock relayLock:
      while cache.len > 0:
        closeEntry(cache.high)
      provider = fonts
      capacity = maxFonts

proc clearUirelaysFontCache*() =
  ## Releases native handles and temporary font files; tokens can reopen later.
  {.cast(gcsafe).}:
    withLock relayLock:
      while cache.len > 0:
        closeEntry(cache.high)

proc clearUirelaysFontCache*(fontId: FontId) =
  {.cast(gcsafe).}:
    withLock relayLock:
      for i in countdown(cache.high, 0):
        if cache[i].fontId == fontId:
          closeEntry(i)

proc clearUirelaysTypefaceCache*(typefaceId: TypefaceId) =
  {.cast(gcsafe).}:
    withLock relayLock:
      for i in countdown(cache.high, 0):
        if cache[i].typefaceId == typefaceId:
          closeEntry(i)

proc cachedRelayFontCount*(): int =
  {.cast(gcsafe).}:
    withLock relayLock:
      result = cache.len

proc devicePixelSize*(font: FigFont, scale: float32): int =
  max(1, round(font.size * scale).int)

proc fontEntry(fontId: FontId, pixelSize: int): int =
  inc useCounter
  for i in 0 ..< cache.len:
    if cache[i].fontId == fontId and cache[i].pixelSize == pixelSize:
      cache[i].lastUse = useCounter
      return i
  if provider.openFont.isNil:
    raise newException(ValueError, "UIRelays font provider is not initialized")
  if cache.len >= capacity:
    var oldest = 0
    for i in 1 ..< cache.len:
      if cache[i].lastUse < cache[oldest].lastUse:
        oldest = i
    closeEntry(oldest)

  let font = getFigFont(fontId)
  let source = getTypefaceSource(font.typefaceId)
  var entry = CachedFont(
    fontId: fontId,
    typefaceId: font.typefaceId,
    pixelSize: pixelSize,
    lastUse: useCounter,
  )
  if source.name.isAbsolute and fileExists(source.name):
    entry.path = source.name
  else:
    let suffix =
      if source.data.len >= 4 and source.data[0 ..< 4] == "ttcf":
        ".ttc"
      elif source.kind == OTF:
        ".otf"
      else:
        ".ttf"
    let (file, path) = createTempFile("figdraw-font-", suffix)
    entry.path = path
    entry.temporary = true
    try:
      try:
        file.write(source.data)
      finally:
        file.close()
    except CatchableError:
      removeTemporary(path)
      raise
  var retained = false
  try:
    if not provider.openFontFace.isNil:
      entry.handle = provider.openFontFace(
        entry.path, source.faceIndex, pixelSize, {}, entry.metrics
      )
    elif source.faceIndex == 0:
      entry.handle = provider.openFont(entry.path, pixelSize, {}, entry.metrics)
    else:
      raise newException(ValueError, "UIRelays cannot select this collection face")
    if entry.handle.int == 0:
      raise newException(ValueError, "UIRelays could not open the typeface")
    cache.add entry
    retained = true
    result = cache.high
  finally:
    if not retained and entry.temporary:
      removeTemporary(entry.path)

proc relayFont*(font: FigFont, scale: float32): RelayFont =
  let fontId = cacheFont(font)
  {.cast(gcsafe).}:
    withLock relayLock:
      let entry = cache[fontEntry(fontId, font.devicePixelSize(scale))]
      result =
        RelayFont(fontId: fontId, pixelSize: entry.pixelSize, metrics: entry.metrics)

proc relayTextWidth*(font: RelayFont, text: string): int =
  {.cast(gcsafe).}:
    withLock relayLock:
      let entry = cache[fontEntry(font.fontId, font.pixelSize)]
      result = provider.measureText(entry.handle, text).w

proc renderRelayGlyph*(
    fontId: FontId, rune: string, pixels: var seq[uint32]
): relays.TextExtent =
  let font = getFigFont(fontId)
  {.cast(gcsafe).}:
    withLock relayLock:
      let entry = cache[fontEntry(fontId, font.devicePixelSize(figUiScale()))]
      result = provider.renderText(
        entry.handle, rune, relays.Color(r: 255, g: 255, b: 255, a: 255), pixels
      )
