# Windows provider smoke test with Wine

This harness cross-compiles the DirectWrite provider test with MinGW and runs
the resulting Windows executable under Wine on an AMD64 Linux Docker host. It
exercises the Windows-only Nim code, COM ABI calls, `dwrite.dll` loading, system
font matching, path extraction, and collection face indices.

The Debian 13 image copies the pinned Nim 2.2.4 toolchain from the official
`nimlang/nim` image because Debian 13 does not package Nim. It installs Debian's
64-bit Wine and MinGW packages, together with Liberation and DejaVu fonts used
as portable test candidates. The test's import closure only needs the Nim
standard library and `src/`, so the harness does not install project packages.

From the repository root, run:

```sh
tools/test-windows-wine.sh
```

The runner uses the `docker1` context by default, which points at the `dockerxx`
host in the FigDraw development environment. Override the context or cached
image name when needed:

```sh
FIGDRAW_DOCKER_CONTEXT=my-context \
  FIGDRAW_WINDOWS_WINE_IMAGE=figdraw/windows-wine-test:local \
  tools/test-windows-wine.sh
```

Wine implements DirectWrite rather than executing Microsoft's implementation.
This is therefore a local ABI and behavior smoke test, not a replacement for
running the same test on Windows. A harmless `syswow64/rundll32.exe` warning may
appear while a fresh 64-bit-only Wine prefix is initialized; the tested binary
and all installed packages are 64-bit.
