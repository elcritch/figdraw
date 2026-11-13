import std/unittest
import pkg/vmath
import ../examples/siwin_svg

suite "SVG viewer navigation":
  test "fit preserves aspect ratio and centers non-square documents":
    var view: SvgView
    view.fit(vec2(900, 450), vec2(800, 600))
    check abs(view.zoom - 752'f32 / 900) < 0.0001
    check abs(view.offset.x - 24) < 0.0001
    check abs(view.offset.y - 112) < 0.0001

  test "zoom keeps the document point under the cursor fixed after panning":
    var view = SvgView(offset: vec2(-120, 80), zoom: 0.6)
    let anchor = vec2(270, 190)
    let point = (anchor - view.offset) / view.zoom
    view.zoomAt(anchor, 1.5)
    check length(view.offset + point * view.zoom - anchor) < 0.001
    view.zoomAt(anchor, 1 / 1.5)
    check length(view.offset - vec2(-120, 80)) < 0.001
    check abs(view.zoom - 0.6) < 0.0001

  test "zoom limits retain the anchor and never invert the view":
    var view = SvgView(offset: vec2(12, 24), zoom: 1)
    let anchor = vec2(400, 300)
    let point = (anchor - view.offset) / view.zoom
    view.zoomAt(anchor, 1000)
    check view.zoom == 32
    check length(view.offset + point * view.zoom - anchor) < 0.001
    view.zoomAt(anchor, 0.000001)
    check view.zoom == 0.01'f32
    check length(view.offset + point * view.zoom - anchor) < 0.001
