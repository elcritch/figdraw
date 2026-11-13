import std/unittest
import pkg/pixie
import chroma
import figdraw/common/texturecompression

suite "BC3 texture compression":
  test "decode independent block with four color palette entries and eight alpha entries":
    var image = CompressedImage(
      format: tcfBc3,
      width: 4,
      height: 4,
      data: @[
        255'u8, 0, 0x88, 0xc6, 0xfa, 0x88, 0xc6, 0xfa, 0x00, 0xf8, 0x1f, 0x00, 0xe4,
        0xe4, 0xe4, 0xe4,
      ],
    )
    let decoded = image.decompressImage()
    check decoded[0, 0] == ColorRGBX(r: 255, g: 0, b: 0, a: 255)
    check decoded[1, 0] == ColorRGBX(r: 0, g: 0, b: 0, a: 0)
    check decoded[2, 0].a == 218
    check decoded[2, 0].r == 145
    check decoded[2, 0].b == 73
    image.data[0] = 0
    image.data[1] = 255
    image.data[2] = 0x3e # indices 6 and 7
    let other = image.decompressImage()
    check other[0, 0].a == 0
    check other[1, 0].a == 255

  test "validation rejects bad sizes and overflow":
    expect ValueError:
      CompressedImage(width: 0, height: 1).validate()
    expect ValueError:
      CompressedImage(width: high(int), height: high(int)).validate()
    expect ValueError:
      CompressedImage(width: 5, height: 1, data: newSeq[uint8](16)).validate()

  test "odd edges and straight alpha round trip":
    let image = newImage(5, 3)
    for y in 0 ..< 3:
      for x in 0 ..< 5:
        image[x, y] = ColorRGBX(r: 100, g: 50, b: 25, a: 128)
    let compressed = image.compressImage()
    check compressed.data.len == 32
    let decoded = compressed.decompressImage()
    check decoded.width == 5
    check decoded.height == 3
    for pixel in decoded.data:
      check abs(pixel.r.int - 100) <= 4
      check abs(pixel.g.int - 50) <= 4
      check abs(pixel.b.int - 25) <= 4
      check pixel.a == 128

  test "contrasting colors retain their distinct channels":
    let image = newImage(4, 4)
    for y in 0 ..< 4:
      for x in 0 ..< 4:
        image[x, y] =
          if x < 2:
            ColorRGBX(r: 255, g: 0, b: 0, a: 255)
          else:
            ColorRGBX(r: 0, g: 255, b: 0, a: 255)
    let decoded = image.compressImage().decompressImage()
    for y in 0 ..< 4:
      for x in 0 ..< 4:
        let p = decoded[x, y]
        if x < 2:
          check p.r.int >= 245
          check p.g.int <= 10
        else:
          check p.g.int >= 245
          check p.r.int <= 10
        check p.b.int <= 10
