import std/[algorithm, locks, os, sets, strutils, tables, unicode]

import ../common/fonttypes
import ../common/typefaceinfos

type
  DisplayServer* = enum
    dsUnknown
    dsWayland
    dsX11

  SystemFontRole* = enum
    sfrSans
    sfrMono

  SystemTypefaceFile* = object
    ## An installed font file and the selected face within it.
    path*: string
    faceIndex*: int

  CachedFontMetadata = object
    valid: bool
    faces: seq[TypefaceInfo]

var
  fontMetadataCache: Table[string, CachedFontMetadata]
  fontMetadataLock: Lock

fontMetadataLock.initLock()

proc normalizeName(name: string): string =
  ## Normalizes a filename for legacy loose matching.
  result = newStringOfCap(name.len)
  for ch in name.toLowerAscii():
    if ch in {'a' .. 'z', '0' .. '9'}:
      result.add(ch)

proc normalizeMetadataName(name: string): string =
  ## Normalizes OpenType names while retaining non-ASCII letters.
  result = newStringOfCap(name.len)
  for rune in name.runes:
    if $rune notin [" ", "-", "_", "."]:
      result.add($rune.toLower)

proc fontNameMatchScore*(requestedName, fontName: string): int =
  ## Ranks a filename or face name for a family request.
  ##
  ## A family name may resolve to an explicitly named regular face, but it
  ## must not resolve to a related family or a styled face. For example,
  ## "Noto Sans" may match "NotoSans-Regular", but not
  ## "NotoSansCJK-Bold" or "NotoSansMono".
  let
    requested = splitFile(requestedName).name.normalizeName()
    candidate = fontName.normalizeName()
  if requested.len == 0 or candidate.len == 0:
    return -1
  if candidate == requested:
    return 0
  if candidate.startsWith(requested):
    let suffix = candidate[requested.len .. ^1]
    if suffix in ["regular", "book", "roman", "normal", "plain", "r"]:
      return 1
  -1

proc systemFontFileMatchScore(requestedName, path: string): int =
  let score = fontNameMatchScore(requestedName, splitFile(path).name)
  if score >= 0:
    return score

  let
    requested = splitFile(requestedName).name.normalizeName()
    stem = splitFile(path).name.normalizeName()
    extension = splitFile(path).ext.toLowerAscii()
  if extension in [".ttc", ".otc"] and requested.startsWith(stem):
    let suffix = requested[stem.len .. ^1]
    if suffix in ["sc", "tc", "hk", "jp", "kr"]:
      return 2
  -1

proc normalizePathKey(path: string): string =
  when defined(windows) or defined(macosx):
    path.toLowerAscii().replace('\\', '/')
  else:
    path.replace('\\', '/')

proc fontMetadataKey(path: string): string =
  path.replace('\\', '/')

proc fontFaceCount(data: string): int =
  if data.len < 12 or data[0 ..< 4] != "ttcf":
    return 1
  result =
    data[8].ord shl 24 or data[9].ord shl 16 or data[10].ord shl 8 or data[11].ord
  if result < 0 or result > (data.len - 12) div 4:
    result = 0

proc readFontMetadata(path: string): CachedFontMetadata =
  try:
    let data = readFile(path)
    let count = data.fontFaceCount()
    if count == 0:
      return
    for faceIndex in 0 ..< count:
      result.faces.add readTypefaceNameInfo(path, data, faceIndex)
    result.valid = result.faces.len > 0
  except CatchableError:
    discard

proc fontMetadata(path: string): CachedFontMetadata =
  let key = fontMetadataKey(path)
  withLock(fontMetadataLock):
    if key in fontMetadataCache:
      return fontMetadataCache[key]
  result = readFontMetadata(path)
  withLock(fontMetadataLock):
    fontMetadataCache[key] = result

proc refreshSystemFontMetadata*() =
  ## Clears cached installed-font metadata after font directories change.
  withLock(fontMetadataLock):
    fontMetadataCache.clear()

proc metadataMatchScore(requestedName: string, info: TypefaceInfo): int =
  let
    requested = requestedName.normalizeMetadataName()
    family = info.family.normalizeMetadataName()
    subfamily = info.subfamily.normalizeMetadataName()
    fullName = info.fullName.normalizeMetadataName()
    postScriptName = info.postScriptName.normalizeMetadataName()
    familyStyle = family & subfamily
  if requested.len == 0 or family.len == 0:
    return -1
  if requested == family:
    let regular =
      if subfamily.len > 0:
        subfamily in ["regular", "normal", "book", "roman"]
      else:
        info.regular
    if regular and not (info.bold or info.italic or info.oblique):
      return 1
    return -1
  if requested == fullName or requested == postScriptName or requested == familyStyle:
    return 0
  -1

proc findSystemTypefaceFile*(
    names, fontFiles: openArray[string], preserveInputOrder = false
): SystemTypefaceFile =
  ## Finds an installed face by OpenType family/style metadata.
  ##
  ## Directories are ranked by their first appearance in `fontFiles`, with
  ## paths sorted within each directory for deterministic ties. Set
  ## `preserveInputOrder` to use the supplied path order without sorting.
  ## Platform discovery supplies user directories before system directories.
  var paths: seq[string]
  if preserveInputOrder:
    paths = @fontFiles
  else:
    var directories: seq[string]
    for path in fontFiles:
      let directory = normalizePathKey(path.parentDir)
      if directory notin directories:
        directories.add(directory)
    for directory in directories:
      var directoryPaths: seq[string]
      for path in fontFiles:
        if normalizePathKey(path.parentDir) == directory:
          directoryPaths.add(path)
      directoryPaths.sort(
        proc(a, b: string): int =
          cmp(normalizePathKey(a), normalizePathKey(b))
      )
      paths.add(directoryPaths)
  for name in names:
    for score in 0 .. 1:
      for path in paths:
        let metadata = path.fontMetadata()
        if metadata.valid:
          for info in metadata.faces:
            if metadataMatchScore(name, info) == score:
              return SystemTypefaceFile(path: path, faceIndex: info.faceIndex)

proc detectDisplayServer*(): DisplayServer =
  ## Detects the display server on non-macOS POSIX platforms.
  when defined(posix) and not defined(macosx):
    if existsEnv("WAYLAND_DISPLAY") and getEnv("WAYLAND_DISPLAY").len > 0:
      return dsWayland
    if existsEnv("DISPLAY") and getEnv("DISPLAY").len > 0:
      return dsX11
  dsUnknown

proc addIfDir(dirs: var seq[string], path: string) =
  if path.len == 0:
    return
  let expanded = path.expandTilde()
  if dirExists(expanded):
    dirs.add(expanded)

proc dedupePaths(paths: openArray[string]): seq[string] =
  var seen = initHashSet[string]()
  for path in paths:
    let key = normalizePathKey(path)
    if key notin seen:
      seen.incl(key)
      result.add(path)

when defined(posix) and not defined(macosx):
  proc splitPathList(value: string): seq[string] =
    for item in value.split(PathSep):
      if item.len > 0:
        result.add(item)

proc systemDefaultFontNames*(role = sfrSans): seq[string] =
  ## Returns platform-default font family candidates for a role.
  when defined(windows):
    case role
    of sfrMono:
      result = @["Cascadia Mono", "Consolas", "Courier New"]
    of sfrSans:
      result = @["Segoe UI", "Arial", "Tahoma", "Verdana"]
  elif defined(macosx):
    case role
    of sfrMono:
      result = @["Menlo", "SF Mono", "Monaco"]
    of sfrSans:
      result = @["Helvetica", "Arial", "SFNS"]
  elif defined(posix):
    case role
    of sfrMono:
      result = @["Noto Sans Mono", "DejaVu Sans Mono", "Liberation Mono", "Ubuntu Mono"]
    of sfrSans:
      result = @["Noto Sans", "DejaVu Sans", "Liberation Sans", "Ubuntu"]
  else:
    discard

proc systemFontDirs*(displayServer = detectDisplayServer()): seq[string] =
  ## Returns existing platform font directories.
  var dirs: seq[string]

  when defined(windows):
    dirs.addIfDir(getEnv("LOCALAPPDATA", "") / "Microsoft" / "Windows" / "Fonts")
    dirs.addIfDir(getEnv("APPDATA", "") / "Microsoft" / "Windows" / "Fonts")
    dirs.addIfDir(getEnv("WINDIR", r"C:\Windows") / "Fonts")
  elif defined(macosx):
    dirs.addIfDir("~/Library/Fonts")
    dirs.addIfDir("/Library/Fonts")
    dirs.addIfDir("/System/Library/Fonts")
  elif defined(posix) and not defined(macosx):
    let home = getHomeDir()
    let xdgDataHome = getEnv("XDG_DATA_HOME", home / ".local" / "share")
    dirs.addIfDir(xdgDataHome / "fonts")

    if displayServer != dsWayland:
      dirs.addIfDir(home / ".fonts")

    for base in splitPathList(getEnv("XDG_DATA_DIRS", "/usr/local/share:/usr/share")):
      dirs.addIfDir(base / "fonts")

    dirs.addIfDir("/usr/share/fonts")
    dirs.addIfDir("/usr/local/share/fonts")

  result = dedupePaths(dirs)

proc systemFontFiles*(displayServer = detectDisplayServer()): seq[string] =
  ## Returns system font files discovered under platform font directories.
  let dirs = systemFontDirs(displayServer)
  var seen = initHashSet[string]()

  for dir in dirs:
    try:
      var files: seq[string]
      for file in walkDirRec(dir):
        let ext = file.splitFile.ext.toLowerAscii()
        if ext in supportedFontFileExtensions():
          files.add(file)
      files.sort()
      for file in files:
        let key = normalizePathKey(file)
        if key notin seen:
          seen.incl(key)
          result.add(file)
    except OSError:
      discard

proc findSystemTypefaceFile*(
    names: openArray[string], displayServer = detectDisplayServer()
): SystemTypefaceFile =
  ## Finds an installed face by OpenType metadata using platform font folders.
  findSystemTypefaceFile(
    names, systemFontFiles(displayServer), preserveInputOrder = true
  )

proc findSystemFontFile*(names, fontFiles: openArray[string]): string =
  ## Finds a preferred font from `fontFiles` matching one of `names`.
  ##
  ## An unstyled family request can match a conventional regular suffix, but
  ## related families and bold, italic, or monospace faces do not qualify.
  if names.len == 0:
    return ""

  for name in names:
    let requestedExt = splitFile(name).ext.toLowerAscii()
    for score in 0 .. 2:
      for path in fontFiles:
        if (requestedExt.len == 0 or splitFile(path).ext.toLowerAscii() == requestedExt) and
            systemFontFileMatchScore(name, path) == score:
          return path
  ""

proc findSystemFontFile*(
    names: openArray[string], displayServer = detectDisplayServer()
): string =
  ## Finds the preferred installed system font path matching one of `names`.
  ##
  ## Named requests use OpenType metadata. The two-array overload remains a
  ## filename-only helper for callers that supply synthetic paths.
  let fontFiles = systemFontFiles(displayServer)
  for name in names:
    if splitFile(name).ext.len > 0:
      let path = findSystemFontFile([name], fontFiles)
      if path.len > 0:
        return path
    let typeface = findSystemTypefaceFile([name], fontFiles, preserveInputOrder = true)
    if typeface.path.len > 0:
      return typeface.path
    let alias = splitFile(name).name.toLowerAscii().replace("-", "")
    if alias in ["sfns", "ubuntur"]:
      let path = findSystemFontFile([name], fontFiles)
      if path.len > 0:
        return path
