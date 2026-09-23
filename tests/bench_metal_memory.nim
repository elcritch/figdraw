## nim c --mm:arc -d:release -o:/tmp/figdraw-metal-bench tests/bench_metal_memory.nim
## /usr/bin/time -l /tmp/figdraw-metal-bench plain
## Reports current Metal allocations; time reports peak process memory.
import std/os

import figdraw/commons

when UseMetalBackend:
  import pkg/[pixie, chroma]
  import darwin/objc/runtime
  import metalx/metal
  import figdraw/figbasics
  import figdraw/metal/metal_context

  proc currentAllocatedSize(
    device: MTLDevice
  ): NSUInteger {.objc: "currentAllocatedSize".}

  if paramCount() != 1 or paramStr(1) notin ["init", "plain", "blur", "shot", "idle"]:
    quit "usage: bench_metal_memory init|plain|blur|shot|idle"

  let scenario = paramStr(1)
  let ctx = newContext(atlasSize = 1024, maxQuads = 1024)
  echo "metal_bytes_init=", currentAllocatedSize(ctx.metalDevice())

  if scenario != "init":
    ctx.beginFrame(vec2(1024, 768), clearMain = true)
    for i in 0 ..< 64:
      ctx.drawRect(rect(float32(i * 8), 0, 8, 64), color(1, 0, 0, 1))
    if scenario in ["blur", "idle"]:
      ctx.drawBackdropBlur(rect(64, 64, 128, 128), default(CornerRadii2D[float32]), 4)
    ctx.endFrame()
    discard ctx.readPixels(rect(0, 0, 1, 1))
    echo "metal_bytes_frame=", currentAllocatedSize(ctx.metalDevice())
    if scenario == "shot":
      let image = ctx.readPixels()
      echo "screenshot_pixels=", image.width * image.height
    elif scenario == "idle":
      for _ in 0 ..< 3:
        ctx.beginFrame(vec2(1024, 768), clearMain = true)
        ctx.drawRect(rect(0, 0, 8, 8), color(1, 0, 0, 1))
        ctx.endFrame()
        discard ctx.readPixels(rect(0, 0, 1, 1))
      echo "metal_bytes_idle=", currentAllocatedSize(ctx.metalDevice())
else:
  quit "Metal backend is required"
