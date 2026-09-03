import std/math

import figdraw

type FragmentExample* = object
  renders*: RenderFragments
  fragment: RenderFragmentHandle
  logicalSize: Vec2
  frame: int

proc makeCards(logicalSize: Vec2, frame: int): RenderList =
  let
    t = frame.float32 * 0.025'f32
    cardWidth = min(180.0'f32, max(80.0'f32, (logicalSize.x - 120.0'f32) / 3.0'f32))
    cardHeight = min(220.0'f32, max(100.0'f32, logicalSize.y * 0.38'f32))
    gap = min(30.0'f32, max(12.0'f32, logicalSize.x * 0.025'f32))
    rowWidth = cardWidth * 3.0'f32 + gap * 2.0'f32
    rowX = (logicalSize.x - rowWidth) * 0.5'f32
    rowY = (logicalSize.y - cardHeight) * 0.5'f32
    drift = sin(t.float64).float32 * min(28.0'f32, logicalSize.x * 0.03'f32)

  let transform = result.addRoot(
    Fig(kind: nkTransform, transform: TransformStyle(translation: vec2(drift, 0.0'f32)))
  )

  let colors =
    [rgba(255, 103, 120, 255), rgba(91, 192, 143, 255), rgba(92, 132, 255, 255)]
  for card in 0 ..< colors.len:
    let
      phase = t + card.float32 * 1.4'f32
      lift = sin(phase.float64).float32 * 24.0'f32
      corner = uint16(18.0'f32 + (sin(phase.float64).float32 + 1.0'f32) * 8.0'f32)
    discard result.addChild(
      transform,
      Fig(
        kind: nkRectangle,
        screenBox: rect(
          rowX + card.float32 * (cardWidth + gap), rowY + lift, cardWidth, cardHeight
        ),
        corners: [corner, corner, corner, corner],
        fill: colors[card],
        stroke: RenderStroke(weight: 3.0'f32, fill: rgba(255, 255, 255, 190)),
        shadows: [
          RenderShadow(
            style: DropShadow,
            blur: 18.0'f32,
            spread: 2.0'f32,
            x: 0.0'f32,
            y: 12.0'f32,
            fill: rgba(30, 38, 65, 70),
          ),
          RenderShadow(),
          RenderShadow(),
          RenderShadow(),
        ],
      ),
    )

proc initFragmentExample*(logicalSize: Vec2): FragmentExample =
  result.logicalSize = logicalSize
  result.renders = newRenderFragments()
  let background = result.renders.addRoot(
    0.ZLevel,
    Fig(
      kind: nkRectangle,
      screenBox: rect(0.0'f32, 0.0'f32, logicalSize.x, logicalSize.y),
      fill: linear(rgba(244, 247, 255, 255), rgba(218, 226, 246, 255), axis = fgaY),
    ),
  )
  result.fragment = result.renders.attachChildFragment(
    0.ZLevel, background, 0, makeCards(logicalSize, 0)
  )

proc resize*(example: var FragmentExample, logicalSize: Vec2) =
  if logicalSize != example.logicalSize:
    let frame = example.frame
    example = initFragmentExample(logicalSize)
    example.frame = frame

proc update*(example: var FragmentExample) =
  inc example.frame
  example.fragment = example.renders.replaceFragment(
    example.fragment, makeCards(example.logicalSize, example.frame)
  )
