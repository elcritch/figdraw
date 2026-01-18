import unicode, vmath, windy/common

when defined(emscripten):
  import windy/platforms/emscripten/platform
elif defined(windows):
  import windy/platforms/win32/platform
elif defined(macosx):
  import windy/platforms/macos/platform
elif defined(linux) or defined(bsd):
  import windy/platforms/linux/platform
else:
  {.error: "windyshim: unsupported OS".}

export common, platform, unicode, vmath
