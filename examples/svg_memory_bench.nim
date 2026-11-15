## Compare layered SVG rendering with a cached full-frame CPU raster on Metal.
## nim c -d:release examples/svg_memory_bench.nim
## /usr/bin/time -l ./examples/svg_memory_bench layered 512
## ./examples/svg_memory_bench raster 512 payload
## `payload` counts image bytes in a separate run: subscription copies affect RSS.
import std/[os, strutils, monotimes, times, json]
import pixie
import pixie/fileformats/svg as pixieSvg
import figdraw
import figdraw/svgs/svg

proc texturePayload(): tuple[count, bytes: int] =
  let subscription = newImageMessageSubscription()
  var message: ImageMsg
  while subscription.tryRecvImageMsg(message):
    if message.kind in {ImkPutPixie, ImkReplacePixie, ImkPutGlyphPixie}:
      inc result.count
      result.bytes += message.pimg.width * message.pimg.height * 4

when isMainModule:
  when not UseMetalBackend:
    quit "This offscreen benchmark requires the Metal backend."
  else:
    let mode =
      if paramCount() > 0:
        paramStr(1)
      else:
        "layered"
    let size =
      if paramCount() > 1:
        parseInt(paramStr(2))
      else:
        512
    if mode notin ["layered", "raster"] or size <= 32:
      quit "Usage: svg_memory_bench layered|raster size [payload]"
    let input = currentSourcePath().parentDir.parentDir / "data/Ghostscript_Tiger.svg"
    let data = readFile(input)
    let target = rect(16, 16, size.float32 - 32, size.float32 - 32)
    let start = getMonoTime()
    var resource: SvgMtsdfResource
    var bitmap: ImageRef
    var list: RenderList
    list.addRoot(
      Fig(
        kind: nkRectangle,
        screenBox: rect(0, 0, size.float32, size.float32),
        fill: fill(rgba(255, 255, 255, 255)),
      )
    )
    if mode == "layered":
      resource = newSvgMtsdfResource(data)
      list.addSvgMtsdf(target, resource)
    else:
      let raster = pixieSvg.parseSvg(data, size - 32, size - 32).newImage()
      bitmap = imageRef(imgId("tiger-benchmark-raster"), raster)
      list.addRoot(Fig(kind: nkImage, screenBox: target, image: imageStyle(bitmap)))
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let prepared = getMonoTime()
    var payload = (count: 0, bytes: 0)
    if paramCount() > 2 and paramStr(3) == "payload":
      payload = texturePayload()
    let renderer = newFigRenderer(atlasSize = 2048)
    renderer.renderFrame(scene, vec2(size.float32))
    renderer.finishPendingFrames()
    let firstFrame = getMonoTime()
    # A screenshot both verifies the rendered result and forces readback.
    createDir("tests/output")
    renderer.takeOneFrameScreenshot().writeFile(
      "tests/output/tiger-bench-" & mode & "-" & $size & ".png"
    )
    let warmStart = getMonoTime()
    for i in 0 ..< 20:
      renderer.renderFrame(scene, vec2(size.float32))
    renderer.finishPendingFrames()
    let atlas = renderer.ctx.atlasSize()
    echo $(
      %*{
        "mode": mode,
        "frameSize": size,
        "prepareMs": (prepared - start).inMicroseconds.float / 1000,
        "setupAndFirstFrameMs": (firstFrame - prepared).inMicroseconds.float / 1000,
        "warmFrameMs": (getMonoTime() - warmStart).inMicroseconds.float / 20000,
        "atlasEdge": atlas,
        "atlasRgbaBytes": atlas * atlas * 4,
        "payloadImageCount": payload.count,
        "payloadRgbaBytes": payload.bytes,
      }
    )
