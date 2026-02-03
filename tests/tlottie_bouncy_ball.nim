import std/[unittest]

import figdraw/lottie/loader
import figdraw/lottie/render
import figdraw/common/imgutils
import figdraw/fignodes

const BouncyBallJson = """
{
  "nm": "Bouncy Ball",
  "v": "5.5.2",
  "ip": 0,
  "op": 120,
  "fr": 60,
  "w": 512,
  "h": 512,
  "layers": [
    {
      "ddd": 0,
      "ty": 4,
      "ind": 0,
      "st": 0,
      "ip": 0,
      "op": 120,
      "nm": "Layer",
      "ks": {
        "a": { "a": 0, "k": [0, 0] },
        "p": { "a": 0, "k": [0, 0] },
        "s": { "a": 0, "k": [100, 100] },
        "r": { "a": 0, "k": 0 },
        "o": { "a": 0, "k": 100 }
      },
      "shapes": [
        {
          "ty": "gr",
          "nm": "Ellipse Group",
          "it": [
            {
              "ty": "el",
              "nm": "Ellipse",
              "p": { "a": 0, "k": [204, 169] },
              "s": { "a": 0, "k": [153, 153] }
            },
            {
              "ty": "fl",
              "nm": "Fill",
              "o": { "a": 0, "k": 100 },
              "c": { "a": 0, "k": [0.710, 0.192, 0.278] },
              "r": 1
            },
            {
              "ty": "tr",
              "a": { "a": 0, "k": [204, 169] },
              "p": {
                "a": 1,
                "k": [
                  { "t": 0, "s": [235, 106], "h": 0,
                    "o": { "x": [0.333], "y": [0] },
                    "i": { "x": [1], "y": [1] }
                  },
                  { "t": 60, "s": [235, 441], "h": 0,
                    "o": { "x": [0], "y": [0] },
                    "i": { "x": [0.667], "y": [1] }
                  },
                  { "t": 120, "s": [235, 106] }
                ]
              },
              "s": {
                "a": 1,
                "k": [
                  { "t": 55, "s": [100, 100], "h": 0,
                    "o": { "x": [0], "y": [0] },
                    "i": { "x": [1], "y": [1] }
                  },
                  { "t": 60, "s": [136, 59], "h": 0,
                    "o": { "x": [0], "y": [0] },
                    "i": { "x": [1], "y": [1] }
                  },
                  { "t": 65, "s": [100, 100] }
                ]
              },
              "r": { "a": 0, "k": 0 },
              "o": { "a": 0, "k": 100 }
            }
          ]
        }
      ]
    }
  ]
}
"""

suite "lottie bouncy ball":
  test "renders mtsdf ellipse at keyframes":
    let anim = parseLottie(BouncyBallJson)
    var renderer = initLottieMtsdfRenderer(anim)

    let renders0 = renderer.renderLottieFrame(0.0'f32)
    let list0 = renders0.layers[0.ZLevel]
    check list0.nodes.len == 2
    let node0 = list0.nodes[1]
    check node0.kind == nkMtsdfImage
    check hasImage(node0.mtsdfImage.id)
    check abs(node0.screenBox.x - 158.5'f32) < 0.5'f32
    check abs(node0.screenBox.y - 29.5'f32) < 0.5'f32
    check abs(node0.screenBox.w - 153.0'f32) < 0.5'f32
    check abs(node0.screenBox.h - 153.0'f32) < 0.5'f32

    let renders60 = renderer.renderLottieFrame(60.0'f32)
    let list60 = renders60.layers[0.ZLevel]
    let node60 = list60.nodes[1]
    check abs(node60.screenBox.x - 131.96'f32) < 1.25'f32
    check abs(node60.screenBox.y - 395.86'f32) < 0.75'f32
    check abs(node60.screenBox.w - 208.08'f32) < 0.75'f32
    check abs(node60.screenBox.h - 90.27'f32) < 0.75'f32
