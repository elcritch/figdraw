when defined(feature.figdraw.cbor):
  import std/unittest
  import figdraw/scenecbor
  import figdraw/fignodes

  suite "CBOR scene protocol":
    test "fixed vectors and hierarchy":
      let scene = Scene(
        nodes: @[
          SceneNode(kind: snGroup, parent: -1, bounds: rect(0, 0, 10, 20)),
          SceneNode(
            kind: snRectangle,
            parent: 0,
            bounds: rect(1, 2, 3, 4),
            color: rgba(255, 0, 0, 255),
          ),
        ]
      )
      let expected =
        "\xa2\x00\x01\x01\x82\x86\x00\x20\x00\x00\x0a\x14" &
        "\x87\x01\x00\x01\x02\x03\x04\x1a\xff\x00\x00\xff"
      check encodeScene(scene) == expected
      for length in 0 ..< expected.len:
        expect SceneWireError:
          discard decodeScene(expected[0 ..< length])
      let decoded = decodeScene(expected)
      check decoded.nodes.len == 2
      check decoded.nodes[1].color == rgba(255, 0, 0, 255)
      let list = decoded.toRenderList()
      check list.rootIds.len == 1
      check list.nodes[0].childCount == 1
      check list.nodes[1].kind == nkRectangle
    test "text and resource ids round trip":
      let scene = Scene(
        nodes: @[
          SceneNode(
            kind: snText,
            parent: -1,
            bounds: rect(0.5, -3, 10, 12),
            fontId: 42,
            text: "hello λ",
            textColor: rgba(1, 2, 3, 4),
          ),
          SceneNode(
            kind: snImage, parent: -1, bounds: rect(1, 1, 2, 2), imageId: high(uint64)
          ),
        ]
      )
      let decoded = decodeScene(encodeScene(scene))
      check decoded.nodes[0].text == "hello λ"
      check decoded.nodes[0].bounds.x == 0.5
      check decoded.nodes[1].imageId == high(uint64)
      expect SceneWireError:
        discard decoded.toRenderList()
      var seen = false
      let resolveText: TextResolver = proc(
          id: uint64, text: string, bounds: Rect, color: ColorRGBA
      ): GlyphArrangement =
        check id == 42
        check text == "hello λ"
        check bounds.x == 0.5
        check color == rgba(1, 2, 3, 4)
        seen = true
        default(GlyphArrangement)
      let resolveImage: ImageResolver = proc(id: uint64): ImageId =
        check id == high(uint64)
        default(ImageId)
      let list = decoded.toRenderList(resolveText, resolveImage)
      check seen
      check list.nodes[0].kind == nkText
      check list.nodes[1].kind == nkImage
    test "reject malformed data":
      for data in [
        "", "\xa2\x00\x02\x01\x80", "\xa2\x00\x01\x01\x80\x00",
        "\xa2\x00\x01\x01\x81\x83\x00\x00\x84\x00\x00\x00\x00",
        "\xa2\x00\x01\x01\x9f\xff", "\xa2\x00\x01\x01\x81\x83\x18",
        "\xa2\x00\x01\x01\x81\x83\x00\x3b\xff\xff\xff\xff\xff\xff\xff\xff\x84\x00\x00\x00\x00",
      ]:
        expect SceneWireError:
          discard decodeScene(data)
      expect SceneWireError:
        discard encodeScene(Scene(nodes: @[SceneNode(kind: snGroup, parent: 0)]))
      expect SceneWireError:
        discard encodeScene(
          Scene(nodes: @[SceneNode(kind: snText, parent: -1, text: "\xff")])
        )

    test "reject invalid protocol fields and limits":
      let prefix = "\xa2\x00\x01\x01\x81"
      let group = "\x86\x00\x20\x00\x00\x00\x00"
      let invalid = [
        "\xa2\x00\x01\x00\x80", # duplicate key
        "\xa2\x00\x01\x02\x80", # unknown key
        prefix & "\x86\x04\x20\x00\x00\x00\x00", # unknown kind
        prefix & "\x86\x00\x20\xfa\x7f\x80\x00\x00\x00\x00\x00", # infinity
        prefix & "\x86\x00\x20\xfa\x00", # truncated float
        prefix & "\x87\x01\x20\x00\x00\x00\x00\x1b\x00\x00\x00\x01\x00\x00\x00\x00",
        "\xa2\x00\x01\x01\x99\x80\x00", # oversized node count
        prefix & "\x88\x02\x20\x00\x00\x00\x00\x00\x7a\x00\x10\x00\x01",
        "\xc0" & prefix & group, # unsupported tag
      ]
      for data in invalid:
        expect SceneWireError:
          discard decodeScene(data)

    test "default text color is omitted and restored":
      let scene = Scene(nodes: @[SceneNode(kind: snText, text: "a")])
      let bytes = encodeScene(scene)
      check bytes == "\xa2\x00\x01\x01\x81\x88\x02\x20\x00\x00\x00\x00\x00\x61a"
      check decodeScene(bytes).nodes[0].textColor == rgba(0, 0, 0, 255)
