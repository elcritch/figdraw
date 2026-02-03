import std/[os, unittest]

import figdraw/lottie/loader
import figdraw/lottie/render
import figdraw/common/imgutils
import figdraw/fignodes
import figdraw/commons

suite "lottie bouncy ball":
  test "renders mtsdf ellipse at keyframes":
    setFigDataDir(getCurrentDir() / "data")
    let anim = loadLottieFile(figDataDir() / "lottie" / "bouncy_ball.json")
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
