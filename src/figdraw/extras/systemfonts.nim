import std/[os, strutils, sets]

import ../common/fonttypes

type
  DisplayServer* = enum
    dsUnknown
    dsWayland
    dsX11

  SystemFontRole* = enum
    sfrSans
    sfrMono

proc normalizeName(name: string): string =
  ## Normalizes a font/file name for loose matching.
  result = newStringOfCap(name.len)
  for ch in name.toLowerAscii():
    if ch in {'a' .. 'z', '0' .. '9'}:
      result.add(ch)

proc normalizePathKey(path: string): string =
  path.toLowerAscii().replace('\\', '/')

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
    dirs.addIfDir(getEnv("WINDIR", r"C:\Windows") / "Fonts")
    dirs.addIfDir(getEnv("LOCALAPPDATA", "") / "Microsoft" / "Windows" / "Fonts")
    dirs.addIfDir(getEnv("APPDATA", "") / "Microsoft" / "Windows" / "Fonts")
  elif defined(macosx):
    dirs.addIfDir("/System/Library/Fonts")
    dirs.addIfDir("/Library/Fonts")
    dirs.addIfDir("~/Library/Fonts")
  elif defined(posix) and not defined(macosx):
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
        if ext in supportedFontFileExtensions():
          let key = normalizePathKey(file)
          if key notin seen:
            seen.incl(key)
            result.add(file)
    except OSError:
      discard

proc findSystemFontFile*(
    names: openArray[string], displayServer = detectDisplayServer()
): string =
  ## Finds the preferred system font path matching one of the candidate names.
  ##
  ## Exact normalized file and stem matches take precedence over loose partial
  ## matches, so a request such as "Times New Roman" is not captured by
  ## "Times.ttc" before "Times New Roman.ttf" is considered.
  if names.len == 0:
    return ""

  let fontFiles = systemFontFiles(displayServer)
  for name in names:
    let candidate = name.normalizeName()
    if candidate.len == 0:
      continue
    for path in fontFiles:
      let
        parts = splitFile(path)
        stem = parts.name.normalizeName()
        fileName = (parts.name & parts.ext).normalizeName()
      if candidate == stem or candidate == fileName:
        return path

  for name in names:
    let candidate = name.normalizeName()
    if candidate.len == 0:
      continue
    for path in fontFiles:
      let stem = splitFile(path).name.normalizeName()
      if stem.contains(candidate) or candidate.contains(stem):
        return path
  ""
