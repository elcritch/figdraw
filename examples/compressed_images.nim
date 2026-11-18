## Compare an RGBA image with opt-in BC3 using the same offscreen Metal scene.
## nim r -d:release examples/compressed_images.nim [rgba|bc3] [size] [output.png]
import std/[os, strutils, monotimes, times, json]
import pixie
import pixie/fileformats/svg as pixieSvg
import figdraw

when isMainModule:
  when not UseMetalBackend:
    quit "This offscreen example requires the Metal backend."
  else:
    let mode =
      if paramCount() > 0:
        paramStr(1)
      else:
        "bc3"
    let size =
      if paramCount() > 1:
        parseInt(paramStr(2))
      else:
        512
    if mode notin ["rgba", "bc3"] or size <= 32:
      quit "Usage: compressed_images [rgba|bc3] [size>32] [output.png]"
    let input = currentSourcePath().parentDir.parentDir / "data/Ghostscript_Tiger.svg"
    let raster = pixieSvg.parseSvg(readFile(input), size - 32, size - 32).newImage()
    let sourceBytes = raster.width * raster.height * 4
    let payloadBytes = ((raster.width + 3) div 4) * ((raster.height + 3) div 4) * 16
    var encodeMs = 0.0
    var bitmap: ImageRef
    let id = imgId("compressed-images-tiger")
    if mode == "bc3":
      let start = getMonoTime()
      let compressed = raster.compressImage()
      encodeMs = (getMonoTime() - start).inMicroseconds.float / 1000
      bitmap = imageRef(id, compressed)
    else:
      bitmap = imageRef(id, raster)
    var list: RenderList
    list.addRoot(
      Fig(
        kind: nkRectangle,
        screenBox: rect(0, 0, size.float32, size.float32),
        fill: fill(rgba(255, 255, 255, 255)),
      )
    )
    list.addRoot(
      Fig(
        kind: nkImage,
        screenBox: rect(16, 16, size.float32 - 32, size.float32 - 32),
        image: imageStyle(bitmap),
      )
    )
    var scene = newRenders()
    scene.setLayer(0.ZLevel, list)
    let renderer = newFigRenderer(atlasSize = 64)
    renderer.renderFrame(scene, vec2(size.float32))
    renderer.finishPendingFrames()
    if paramCount() > 2:
      renderer.takeOneFrameScreenshot().writeFile(paramStr(3))
    echo $(
      %*{
        "mode": mode,
        "sourceRgbaBytes": sourceBytes,
        "bc3PayloadBytes": payloadBytes,
        "supportsNative": renderer.ctx.supportsTextureCompression(tcfBc3),
        "compressedTextureBytes": renderer.ctx.compressedTextureBytes(),
        "compressedTextureCount": renderer.ctx.compressedTextureCount(),
        "actualAtlasSize": renderer.ctx.atlasSize(),
        "encodeMs": encodeMs,
      }
    )
    discard bitmap.id
