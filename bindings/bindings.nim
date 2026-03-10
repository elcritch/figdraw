import genny
import figdraw/commons

exportProcs:
  figDataDir
  setFigDataDir
  figUiScale
  setFigUiScale
  scaled(float32)
  descaled(float32)

writeFiles("bindings/generated", "FigDraw")

include generated/internal
