import std/[os, json]

import pkg/chronicles

import appframes

type WindowConfig* = object
  pos*: IVec2 = ivec2(100, 100)
  size*: IVec2 = ivec2(0, 0)

proc windowCfgFile*(frame: AppFrame): string =
  frame[].configFile & ".window"

proc loadLastWindow*(frame: AppFrame): WindowConfig =
  result = WindowConfig()
  if frame.windowCfgFile().fileExists():
    try:
      let jn = parseFile(frame.windowCfgFile())
      result = jn.to(WindowConfig)
    except Defect, CatchableError:
      discard
  notice "loadLastWindow", config = result

proc writeWindowConfig*(wcfg: WindowConfig, winCfgFile: string) =
  try:
    let jn = %*(wcfg)
    writeFile(winCfgFile, $(jn))
  except Defect, CatchableError:
    debug "error writing window position"
