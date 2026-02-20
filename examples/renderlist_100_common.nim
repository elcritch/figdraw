import std/[random, math]

import chroma

import figdraw/commons
import figdraw/fignodes

const copies {.intdefine: "figdraw.nodes".} = 100

proc makeRenderTree*(w, h: float32, frame: int): Renders =
  var list = RenderList()
  let t = frame.float32 * 0.02'f32

  discard list.addRoot(
    Fig(
      kind: nkRectangle,
      childCount: 0,
      zlevel: 0.ZLevel,
      screenBox: rect(0, 0, w, h),
      fill: rgba(255, 255, 255, 155),
    )
  )

  let redStartX = 60.0'f32
  let redStartY = 60.0'f32
  let greenStartX = 320.0'f32
  let greenStartY = 120.0'f32
  let blueStartX = 180.0'f32
  let blueStartY = 300.0'f32

  let maxW = 260.0'f32
  let maxH = 180.0'f32
  let maxX = max(0.0'f32, w - (greenStartX + maxW))
  let maxY = max(0.0'f32, h - (blueStartY + maxH))
  #var rng = initRand((w.int shl 16) xor h.int xor 12345)
  var rng = initRand(12345)

  for i in 0 ..< copies:
    let baseX = rand(rng, 0.0'f32 .. maxX)
    let baseY = rand(rng, 0.0'f32 .. maxY)
    let jitterX = sin((t + i.float32 * 0.15'f32).float64).float32 * 20
    let jitterY = cos((t * 0.9'f32 + i.float32 * 0.2'f32).float64).float32 * 20
    let offsetX = min(max(baseX + jitterX, 0.0'f32), maxX)
    let offsetY = min(max(baseY + jitterY, 0.0'f32), maxY)

    let sizePulseW =
      0.5'f32 + 0.5'f32 * sin((t * 0.8'f32 + i.float32 * 0.07'f32).float64).float32
    let sizePulseH =
      0.5'f32 + 0.5'f32 * cos((t * 0.65'f32 + i.float32 * 0.09'f32).float64).float32

    let redW = 160.0'f32 + 100.0'f32 * sizePulseW
    let redH = 110.0'f32 + 70.0'f32 * sizePulseH
    let greenW = 160.0'f32 + 100.0'f32 * sizePulseH
    let greenH = 110.0'f32 + 70.0'f32 * sizePulseW
    let blueW = 160.0'f32 + 100.0'f32 * (1.0'f32 - sizePulseW)
    let blueH = 110.0'f32 + 70.0'f32 * (1.0'f32 - sizePulseH)

    let cornerPulse =
      0.5'f32 + 0.5'f32 * sin((t * 1.25'f32 + i.float32 * 0.11'f32).float64).float32
    let c0 = 4.0'f32 + 26.0'f32 * cornerPulse
    let c1 = 6.0'f32 + 22.0'f32 * (1.0'f32 - cornerPulse)
    let c2 =
      8.0'f32 +
      18.0'f32 *
      (0.5'f32 + 0.5'f32 * sin((t * 0.7'f32 + i.float32 * 0.05'f32).float64).float32)
    let c3 =
      10.0'f32 +
      16.0'f32 *
      (0.5'f32 + 0.5'f32 * cos((t * 0.8'f32 + i.float32 * 0.06'f32).float64).float32)

    let greenCornerPulse =
      0.5'f32 + 0.5'f32 * cos((t * 0.95'f32 + i.float32 * 0.08'f32).float64).float32
    let g0 = 6.0'f32 + 22.0'f32 * greenCornerPulse
    let g1 = 8.0'f32 + 18.0'f32 * (1.0'f32 - greenCornerPulse)
    let g2 =
      10.0'f32 +
      16.0'f32 *
      (0.5'f32 + 0.5'f32 * cos((t * 0.75'f32 + i.float32 * 0.04'f32).float64).float32)
    let g3 =
      12.0'f32 +
      14.0'f32 *
      (0.5'f32 + 0.5'f32 * sin((t * 0.85'f32 + i.float32 * 0.05'f32).float64).float32)

    let shadowPulse =
      0.5'f32 + 0.5'f32 * sin((t * 1.1'f32 + i.float32 * 0.05'f32).float64).float32
    let shadowBlur = max(0.0'f32, 6.0'f32 + 18.0'f32 * shadowPulse)
    let shadowSpread = max(0.0'f32, 4.0'f32 + 20.0'f32 * (1.0'f32 - shadowPulse))
    let shadowX =
      6.0'f32 + 10.0'f32 * sin((t * 0.9'f32 + i.float32 * 0.03'f32).float64).float32
    let shadowY =
      6.0'f32 + 10.0'f32 * cos((t * 0.9'f32 + i.float32 * 0.03'f32).float64).float32
    let insetPulse =
      0.5'f32 + 0.5'f32 * sin((t * 1.05'f32 + i.float32 * 0.06'f32).float64).float32
    let insetBlur = max(0.0'f32, 8.0'f32 + 10.0'f32 * insetPulse)
    let insetSpread = max(0.0'f32, 2.0'f32 + 10.0'f32 * (1.0'f32 - insetPulse))
    let insetX = 6.0'f32 * sin((t * 0.85'f32 + i.float32 * 0.04'f32).float64).float32
    let insetY = 6.0'f32 * cos((t * 0.8'f32 + i.float32 * 0.04'f32).float64).float32
    let useGreenGradient = (i mod 2) == 0
    let useBlueGradient = (i mod 3) == 0

    discard list.addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        corners: [c0, c1, c2, c3],
        screenBox: rect(redStartX + offsetX, redStartY + offsetY, redW, redH),
        fill: rgba(220, 40, 40, 155),
        stroke: RenderStroke(weight: 5.0, fill: rgba(0, 0, 0, 155).color),
      )
    )

    discard list.addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: rect(greenStartX + offsetX, greenStartY + offsetY, greenW, greenH),
        corners: [g0, g1, g2, g3],
        fill:
          if useGreenGradient:
            fillLinear(
              rgba(18, 112, 64, 255),
              rgba(40, 180, 90, 255),
              rgba(78, 224, 188, 255),
              axis = if (i mod 4) < 2: fgaX else: fgaDiagTLBR,
              midPos = 128'u8,
            )
          else:
            rgba(40, 180, 90, 155),
        shadows: [
          RenderShadow(
            style: DropShadow,
            blur: shadowBlur,
            spread: shadowSpread,
            x: shadowX,
            y: shadowY,
            fill: rgba(0, 0, 0, 155).color,
          ),
          RenderShadow(),
          RenderShadow(),
          RenderShadow(),
        ],
      )
    )

    discard list.addRoot(
      Fig(
        kind: nkRectangle,
        childCount: 0,
        zlevel: 0.ZLevel,
        screenBox: rect(blueStartX + offsetX, blueStartY + offsetY, blueW, blueH),
        fill:
          if useBlueGradient:
            fillLinear(
              rgba(44, 72, 186, 255),
              rgba(60, 90, 220, 255),
              rgba(118, 168, 255, 255),
              axis = if (i mod 2) == 0: fgaY else: fgaDiagBLTR,
              midPos = 132'u8,
            )
          else:
            rgba(60, 90, 220, 155),
        stroke: RenderStroke(weight: 4.0, fill: rgba(255, 255, 255, 210).color),
        shadows: [
          RenderShadow(
            style: InnerShadow,
            blur: insetBlur,
            spread: insetSpread,
            x: insetX,
            y: insetY,
            fill:
              if useBlueGradient:
                fillLinear(
                  rgba(25, 25, 40, 100), rgba(65, 65, 95, 180), axis = fgaDiagBLTR
                )
              else:
                rgba(40, 40, 60, 150),
          ),
          RenderShadow(),
          RenderShadow(),
          RenderShadow(),
        ],
      )
    )

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list
