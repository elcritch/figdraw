## Compare cached MTSDF layers with tightly cropped per-paint RGBA rasters.
## Run each case in a separate process: svg_layer_memory_bench mtsdf|raster SIZE [LONGEDGE]
import std/[json, math, monotimes, os, strutils, times]
import pixie
import figdraw
import figdraw/svgs/[svg, svgpathloader, svgstrokes]

proc matrix(a: SvgAffine): Mat3 =
  result = mat3()
  result[0, 0] = a.a
  result[0, 1] = a.b
  result[1, 0] = a.c
  result[1, 1] = a.d
  result[2, 0] = a.tx
  result[2, 1] = a.ty

proc payload(): tuple[count, bytes: int] =
  let sub = newImageMessageSubscription()
  var msg: ImageMsg
  while sub.tryRecvImageMsg(msg):
    if msg.kind in {ImkPutPixie, ImkReplacePixie, ImkPutGlyphPixie}:
      inc result.count
      result.bytes += msg.pimg.width * msg.pimg.height * 4

when isMainModule:
  when not UseMetalBackend:
    quit "This benchmark requires the Metal backend"
  else:
    let mode =
      if paramCount() > 0:
        paramStr(1)
      else:
        "mtsdf"
    let size =
      if paramCount() > 1:
        parseInt(paramStr(2))
      else:
        480
    let longEdge =
      if paramCount() > 2:
        parseInt(paramStr(3))
      else:
        192
    let measurePayload = paramCount() > 3 and paramStr(4) == "payload"
    if mode notin ["mtsdf", "raster"] or size <= 0 or longEdge <= 6:
      quit "Usage: svg_layer_memory_bench mtsdf|raster size [longEdge] [payload]"
    let data =
      readFile(currentSourcePath().parentDir.parentDir / "data/Ghostscript_Tiger.svg")
    let start = getMonoTime()
    var list: RenderList
    list.addRoot(
      Fig(
        kind: nkRectangle,
        screenBox: rect(0, 0, size.float32, size.float32),
        fill: fill(rgba(255, 255, 255, 255)),
      )
    )
    var svgResource: SvgMtsdfResource
    var retained: seq[ImageRef]
    var paintCount = 0
    if mode == "mtsdf":
      svgResource = newSvgMtsdfResource(data, longEdge = longEdge)
      list.addSvgMtsdf(rect(0, 0, size.float32, size.float32), svgResource)
    else:
      let doc = parseSvgDocument(data)
      let factor = size.float32 / max(doc.viewportSize.x, doc.viewportSize.y)
      for element in doc.elements:
        if element.compositeGroupStarts.len > 0 or element.clipPathIds.len > 0 or
            element.maskIds.len > 0 or element.fillPaintValue.startsWith("url(") or
            element.strokePaintValue.startsWith("url("):
          raise newException(
            ValueError, "Benchmark only supports simple solid tiger layers"
          )
        var paths: seq[tuple[path: Path, paint: Color, rule: WindingRule]]
        if element.hasFill:
          paths.add((element.fillPath, element.fillColor, element.fillRule))
        if element.hasStroke:
          let cap =
            case element.strokeCap
            of sscButt: ButtCap
            of sscRound: RoundCap
            of sscSquare: SquareCap
          let join =
            case element.strokeJoin
            of ssjMiter: MiterJoin
            of ssjRound: RoundJoin
            of ssjBevel: BevelJoin
          let outline = strokeOutline(
            element.strokePath, element.sourceStrokeWidth, cap, join,
            element.strokeMiterLimit, element.strokeDashArray, element.strokeDashOffset,
          )
          outline.transform(element.sourceTransform.matrix())
          paths.add((outline, element.strokeColor, NonZero))
        for item in paths:
          let b = item.path.computeBounds()
          if b.w <= 0 or b.h <= 0:
            continue
          let x = floor(b.x * factor).int - 2
          let y = floor(b.y * factor).int - 2
          let w = ceil((b.x + b.w) * factor).int - x + 2
          let h = ceil((b.y + b.h) * factor).int - y + 2
          let bitmap = newImage(w, h)
          bitmap.fillPath(
            item.path,
            item.paint,
            translate(vec2(-x.float32, -y.float32)) * scale(vec2(factor)),
            item.rule,
          )
          let refImage = imageRef(imgId("svg-layer-bench:" & $paintCount), bitmap)
          retained.add refImage
          list.addRoot(
            Fig(
              kind: nkImage,
              screenBox: rect(x.float32, y.float32, w.float32, h.float32),
              image: imageStyle(refImage),
            )
          )
          inc paintCount
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let prepared = getMonoTime()
    let stats =
      if measurePayload:
        payload()
      else:
        (count: 0, bytes: 0)
    let renderer = newFigRenderer(atlasSize = 2048)
    renderer.renderFrame(scene, vec2(size.float32))
    renderer.finishPendingFrames()
    let first = getMonoTime()
    createDir("tests/output")
    renderer.takeOneFrameScreenshot().writeFile(
      "tests/output/layer-bench-" & mode & "-" & $size & "-" & $longEdge & ".png"
    )
    let warm = getMonoTime()
    for i in 0 ..< 20:
      renderer.renderFrame(scene, vec2(size.float32))
    renderer.finishPendingFrames()
    echo $(
      %*{
        "mode": mode,
        "size": size,
        "longEdge": longEdge,
        "paintCount": paintCount,
        "payloadCount": stats.count,
        "payloadBytes": stats.bytes,
        "prepareMs": (prepared - start).inMicroseconds.float / 1000,
        "firstFrameMs": (first - prepared).inMicroseconds.float / 1000,
        "warmFrameMs": (getMonoTime() - warm).inMicroseconds.float / 20000,
        "atlasEdge": renderer.ctx.atlasSize(),
      }
    )
    discard retained.len
