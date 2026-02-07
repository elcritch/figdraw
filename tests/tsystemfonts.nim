import std/[os, unittest]

import figdraw/extras/systemfonts

suite "system fonts":
  test "system font dirs are discoverable":
    let dirs = systemFontDirs()
    check dirs.len > 0

  test "system font files are discoverable":
    let fonts = systemFontFiles()
    check fonts.len > 0

  when defined(windows):
    test "find common windows system font":
      let font =
        findSystemFontFile(["Arial", "Segoe UI", "Tahoma", "Verdana", "Calibri"])
      check font.len > 0
      check fileExists(font)
  elif defined(macosx):
    test "find common macos system font":
      let font = findSystemFontFile(["Helvetica", "Arial", "Menlo", "SFNS"])
      check font.len > 0
      check fileExists(font)
  elif defined(linux) or defined(freebsd):
    test "detect display server from environment":
      let oldWayland = getEnv("WAYLAND_DISPLAY", "")
      let oldDisplay = getEnv("DISPLAY", "")
      let hadWayland = existsEnv("WAYLAND_DISPLAY")
      let hadDisplay = existsEnv("DISPLAY")

      putEnv("WAYLAND_DISPLAY", "wayland-1")
      putEnv("DISPLAY", "")
      check detectDisplayServer() == dsWayland

      putEnv("WAYLAND_DISPLAY", "")
      putEnv("DISPLAY", ":0")
      check detectDisplayServer() == dsX11

      if hadWayland:
        putEnv("WAYLAND_DISPLAY", oldWayland)
      else:
        delEnv("WAYLAND_DISPLAY")

      if hadDisplay:
        putEnv("DISPLAY", oldDisplay)
      else:
        delEnv("DISPLAY")

    test "linux/freebsd supports wayland and x11 directory resolution":
      let x11Dirs = systemFontDirs(dsX11)
      let waylandDirs = systemFontDirs(dsWayland)
      check x11Dirs.len > 0
      check waylandDirs.len > 0

    test "find common linux/freebsd system font":
      let font =
        findSystemFontFile(["DejaVu Sans", "Noto Sans", "Liberation Sans", "Ubuntu"])
      check font.len > 0
      check fileExists(font)
  else:
    test "unsupported platform":
      check true
