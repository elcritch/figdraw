## sdfy distance packets for custom software image sampling.
import pkg/vmath
import pkg/sdfy/spans

export RoundedBoxField, distance

const WantSdfySimd* {.booldefine: "figdraw.sdfySimd".} = true
const softwareSimdEnabled* = spanSimdEnabled and WantSdfySimd

proc roundedBoxField*(halfSize: Vec2, rx, ry: Vec4): RoundedBoxField =
  initRoundedBoxField(halfSize, rx, ry)

proc distances*(field: RoundedBoxField, points: array[4, Vec2]): array[4, float32] =
  spans.distances(field, points, useSimd = softwareSimdEnabled)
