## Opt-in lossy BC3 compression for static, linear UNORM color images.
## Blocks contain straight RGBA, in top-to-bottom order, with mip level zero only.
import pkg/pixie
import chroma

type
  TextureCompressionFormat* = enum
    tcfBc3

  CompressedImage* = object
    format*: TextureCompressionFormat
    width*, height*: int
    data*: seq[uint8]

proc validate*(image: CompressedImage) =
  ## Reject invalid dimensions, overflow, and incorrectly sized block data.
  if image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "compressed image dimensions must be positive")
  let bw = image.width div 4 + ord(image.width mod 4 != 0)
  let bh = image.height div 4 + ord(image.height mod 4 != 0)
  if bw > high(int) div 16 or bh > high(int) div (bw * 16) or
      image.data.len != bw * bh * 16:
    raise newException(ValueError, "invalid compressed image data size")

type Pixel = array[4, int]

proc rgb565(p: Pixel): int =
  ((p[0] * 31 + 127) div 255 shl 11) or ((p[1] * 63 + 127) div 255 shl 5) or
    ((p[2] * 31 + 127) div 255)

proc unpack565(c: int): Pixel =
  let r = (c shr 11) and 31
  let g = (c shr 5) and 63
  let b = c and 31
  [(r shl 3) or (r shr 2), (g shl 2) or (g shr 4), (b shl 3) or (b shr 2), 255]

proc colors(c0, c1: int): array[4, Pixel] =
  result[0] = unpack565(c0)
  result[1] = unpack565(c1)
  for k in 0 .. 2:
    result[2][k] = (2 * result[0][k] + result[1][k]) div 3
    result[3][k] = (result[0][k] + 2 * result[1][k]) div 3
  result[2][3] = 255
  result[3][3] = 255

proc alphas(a0, a1: int): array[8, int] =
  result[0] = a0
  result[1] = a1
  if a0 > a1:
    for i in 1 .. 6:
      result[i + 1] = ((7 - i) * a0 + i * a1) div 7
  else:
    for i in 1 .. 4:
      result[i + 1] = ((5 - i) * a0 + i * a1) div 5
    result[6] = 0
    result[7] = 255

proc decompressImage*(image: CompressedImage): Image =
  ## Decode BC3 into Pixie's premultiplied pixel representation.
  image.validate()
  result = newImage(image.width, image.height)
  var offset = 0
  for by in 0 ..< (image.height div 4 + ord(image.height mod 4 != 0)):
    for bx in 0 ..< (image.width div 4 + ord(image.width mod 4 != 0)):
      let ap = alphas(image.data[offset].int, image.data[offset + 1].int)
      var abits = 0'u64
      for i in 0 .. 5:
        abits = abits or (image.data[offset + 2 + i].uint64 shl (8 * i))
      let c0 = image.data[offset + 8].int or (image.data[offset + 9].int shl 8)
      let c1 = image.data[offset + 10].int or (image.data[offset + 11].int shl 8)
      let cp = colors(c0, c1)
      var cbits = 0'u32
      for i in 0 .. 3:
        cbits = cbits or (image.data[offset + 12 + i].uint32 shl (8 * i))
      for i in 0 .. 15:
        let x = bx * 4 + i mod 4
        let y = by * 4 + i div 4
        if x < image.width and y < image.height:
          let a = ap[int((abits shr (3 * i)) and 7)]
          let c = cp[int((cbits shr (2 * i)) and 3)]
          result[x, y] = ColorRGBX(
            r: uint8((c[0] * a + 127) div 255),
            g: uint8((c[1] * a + 127) div 255),
            b: uint8((c[2] * a + 127) div 255),
            a: uint8(a),
          )
      offset += 16

proc compressImage*(image: Image, format = tcfBc3): CompressedImage =
  ## Compress static color pixels. Glyph and SDF images should remain uncompressed.
  if image.isNil or image.width <= 0 or image.height <= 0:
    raise newException(ValueError, "image dimensions must be positive")
  let bw = image.width div 4 + ord(image.width mod 4 != 0)
  let bh = image.height div 4 + ord(image.height mod 4 != 0)
  if bw > high(int) div 16 or bh > high(int) div (bw * 16):
    raise newException(ValueError, "compressed image dimensions overflow")
  result = CompressedImage(
    format: format,
    width: image.width,
    height: image.height,
    data: newSeq[uint8](bw * bh * 16),
  )
  var offset = 0
  for by in 0 ..< bh:
    for bx in 0 ..< bw:
      var pixels: array[16, Pixel]
      var lo = [255, 255, 255, 255]
      var hi = [0, 0, 0, 0]
      for i in 0 .. 15:
        let p = image[
          min(bx * 4 + i mod 4, image.width - 1),
          min(by * 4 + i div 4, image.height - 1),
        ]
        let a = p.a.int
        pixels[i] = [
          if a == 0:
            0
          else:
            min(255, (p.r.int * 255 + a div 2) div a),
          if a == 0:
            0
          else:
            min(255, (p.g.int * 255 + a div 2) div a),
          if a == 0:
            0
          else:
            min(255, (p.b.int * 255 + a div 2) div a),
          a,
        ]
        for k in 0 .. 3:
          lo[k] = min(lo[k], pixels[i][k])
          hi[k] = max(hi[k], pixels[i][k])
      result.data[offset] = hi[3].uint8
      result.data[offset + 1] = lo[3].uint8
      let ap = alphas(hi[3], lo[3])
      var abits = 0'u64
      for i in 0 .. 15:
        var best = 0
        for j in 1 .. 7:
          if abs(ap[j] - pixels[i][3]) < abs(ap[best] - pixels[i][3]):
            best = j
        abits = abits or (best.uint64 shl (3 * i))
      for i in 0 .. 5:
        result.data[offset + 2 + i] = uint8((abits shr (8 * i)) and 255)
      # Choose endpoints from actual visible colors. Component-wise extrema can
      # produce colors absent from the block (for example yellow and black for
      # a red/green block). Weight by the lower alpha so invisible RGB cannot
      # pull the palette away from visible pixels.
      var first = 0
      var second = 0
      var bestDistance = -1
      for i in 0 .. 15:
        for j in i .. 15:
          var distance = 0
          for k in 0 .. 2:
            let delta = pixels[i][k] - pixels[j][k]
            distance += delta * delta
          distance *= min(pixels[i][3], pixels[j][3])
          if distance > bestDistance:
            bestDistance = distance
            first = i
            second = j
      if bestDistance == 0:
        for i in 1 .. 15:
          if pixels[i][3] > pixels[first][3]:
            first = i
        second = first
      let c0 = rgb565(pixels[first])
      let c1 = rgb565(pixels[second])
      result.data[offset + 8] = uint8(c0 and 255)
      result.data[offset + 9] = uint8(c0 shr 8)
      result.data[offset + 10] = uint8(c1 and 255)
      result.data[offset + 11] = uint8(c1 shr 8)
      let cp = colors(c0, c1)
      var cbits = 0'u32
      for i in 0 .. 15:
        var best = 0
        var bestError = high(int)
        for j in 0 .. 3:
          var error = 0
          for k in 0 .. 2:
            error += (cp[j][k] - pixels[i][k]) * (cp[j][k] - pixels[i][k])
          if error < bestError:
            best = j
            bestError = error
        cbits = cbits or (best.uint32 shl (2 * i))
      for i in 0 .. 3:
        result.data[offset + 12 + i] = uint8((cbits shr (8 * i)) and 255)
      offset += 16
