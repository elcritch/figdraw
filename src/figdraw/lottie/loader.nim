import std/[json, os]

import std/jsonutils

import ./types

proc parseLottie*(data: string): LottieAnimation =
  let node = parseJson(data)
  result = node.jsonTo(LottieAnimation, LottieJsonOptions)

proc loadLottieFile*(path: string): LottieAnimation =
  parseLottie(readFile(path))
