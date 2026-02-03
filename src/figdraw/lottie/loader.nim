import ./types
import pkg/jsony

proc parseLottie*(data: string): LottieAnimation =
  jsony.fromJson(data, LottieAnimation)

proc loadLottieFile*(path: string): LottieAnimation =
  parseLottie(readFile(path))
