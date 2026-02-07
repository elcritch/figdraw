import std/[os, strutils, sequtils, sets]

type
  DisplayServer* = enum
    dsUnknown
    dsWayland
    dsX11

const
  FontFileExtensions = [".ttf", ".ttc", ".otf", ".otc"]

proc normalizeName(name: string): string =
  ## Normalizes a font/file name for loose matching.
  result = newStringOfCap(name.len)
  for ch in name.toLowerAscii():
    if ch in {'a'..'z', '0'..'9'}:
      result.add(ch)

proc normalizePathKey(path: string): string =
  path.toLowerAscii().replace('\\', '/')

proc detectDisplayServer*(): DisplayServer =
  ## Detects Linux/FreeBSD display server. Other platforms return dsUnknown.
  when defined(linux) or defined(freebsd):
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

proc splitPathList(value: string): seq[string] =
  for item in value.split(PathSep):
    if item.len > 0:
      result.add(item)

proc systemFontDirs*(displayServer = detectDisplayServer()): seq[string] =
  ## Returns existing platform font directories.
  var dirs: seq[string]

  when defined(windows):
    dirs.addIfDir(getEnv("WINDIR", r"C:\Windows") / "Fonts")
    dirs.addIfDir(getEnv("LOCALAPPDATA", "") / "Microsoft" / "Windows" / "Fonts")
    dirs.addIfDir(getEnv("APPDATA", "") / "Microsoft" / "Windows" / "Fonts")

  elif defined(macosx):
    dirs.addIfDir("/System/Library/Fonts")
    dirs.addIfDir("/Library/Fonts")
    dirs.addIfDir("~/Library/Fonts")

  elif defined(linux) or defined(freebsd):
    let home = getHomeDir()
    let xdgDataHome = getEnv("XDG_DATA_HOME", home / ".local" / "share")
    dirs.addIfDir(xdgDataHome / "fonts")

    for base in splitPathList(getEnv("XDG_DATA_DIRS", "/usr/local/share:/usr/share")):
      dirs.addIfDir(base / "fonts")

    dirs.addIfDir("/usr/share/fonts")
    dirs.addIfDir("/usr/local/share/fonts")

    if displayServer == dsX11:
      dirs.addIfDir(home / ".fonts")
    elif displayServer == dsWayland:
      # Wayland desktops typically use XDG font directories.
      discard
    else:
      dirs.addIfDir(home / ".fonts")

  result = dedupePaths(dirs)

proc systemFontFiles*(displayServer = detectDisplayServer()): seq[string] =
  ## Returns system font files discovered under platform font directories.
  let dirs = systemFontDirs(displayServer)
  var seen = initHashSet[string]()

  for dir in dirs:
    try:
      for file in walkDirRec(dir):
        let ext = file.splitFile.ext.toLowerAscii()
        if ext in FontFileExtensions:
          let key = normalizePathKey(file)
          if key notin seen:
            seen.incl(key)
            result.add(file)
    except OSError:
      discard

proc findSystemFontFile*(names: openArray[string], displayServer = detectDisplayServer()): string =
  ## Finds the first system font path matching one of the candidate names.
  if names.len == 0:
    return ""

  let candidates = names.toSeq().mapIt(it.normalizeName())
  for path in systemFontFiles(displayServer):
    let stem = splitFile(path).name.normalizeName()
    for candidate in candidates:
      if candidate.len == 0:
        continue
      if stem == candidate or stem.contains(candidate) or candidate.contains(stem):
        return path
  ""
