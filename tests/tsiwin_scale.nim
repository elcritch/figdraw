import std/[os, unittest]

import figdraw/common/shared
import figdraw/windowing/siwinshim

suite "siwin scale":
  test "X11 content scale ignores Xft.dpi because window size is physical pixels":
    when defined(linux) or defined(bsd):
      block runNativeWindow:
        if getEnv("DISPLAY").len == 0:
          skip()
          break runNativeWindow

        let
          oldPath = getEnv("PATH")
          fakeBin = getTempDir() / "figdraw-fake-xrdb-" & $getCurrentProcessId()
          fakeXrdb = fakeBin / "xrdb"
        createDir(fakeBin)
        writeFile(fakeXrdb, "#!/bin/sh\nprintf 'Xft.dpi:\\t144\\n'\n")
        setFilePermissions(
          fakeXrdb,
          {
            fpUserRead, fpUserWrite, fpUserExec, fpGroupRead, fpGroupExec, fpOthersRead,
            fpOthersExec,
          },
        )
        putEnv("PATH", fakeBin & PathSep & oldPath)
        defer:
          putEnv("PATH", oldPath)
          removeDir(fakeBin)
          setFigUiScale(1.0'f32)

        let window = newSiwinWindow(
          size = ivec2(320'i32, 180'i32),
          fullscreen = false,
          title = "figdraw test: x11 scale",
        )
        try:
          if window.siwinDisplayServerName() != "x11":
            skip()
          else:
            check window.contentScale() == window.uiScale()
            discard window.configureUiScale()
            check figUiScale() == window.uiScale()
        finally:
          window.close()
    else:
      skip()
