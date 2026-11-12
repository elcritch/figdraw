import std/unittest
import pkg/pixie
import figdraw/svgs/svgpathloader

suite "SVG path loader":
  test "parses paths and inherited paint in document coordinates":
    let document = parseSvgDocument(
      """
<svg viewBox="0 0 24 16"><g fill="#123456" transform="translate(2 3)">
  <path d="M0 0 H20 V10 H0 Z"/>
</g></svg>
"""
    )
    check document.width == 24
    check document.height == 16
    check document.elements.len == 1
    check document.elements[0].kind == sekPath
    check document.elements[0].hasFill
    check document.elements[0].fillPath.computeBounds() == rect(2, 3, 20, 10)

  test "normalizes endpoint arcs for fill and stroke generation":
    let document = parseSvgDocument(
      """
<svg viewBox="0 0 40 40">
  <path d="M5 20 A15 10 30 0 1 35 20 Z" fill="red" stroke="blue"/>
</svg>
"""
    )
    check document.elements.len == 1
    check document.elements[0].hasFill
    check document.elements[0].hasStroke
    check document.elements[0].strokeSegments.len > 1
    check document.elements[0].strokeSegments[0].kind == sskCubic

  test "keeps line cap, join and transformed stroke width":
    let document = parseSvgDocument(
      """
<svg viewBox="0 0 40 40">
  <path d="M1 2 Q3 4 5 6 T9 10" fill="none" stroke="black"
    stroke-width="2" stroke-linecap="square" stroke-linejoin="bevel"
    transform="scale(2)"/>
</svg>
"""
    )
    let element = document.elements[0]
    check element.strokeCap == sscSquare
    check element.strokeJoin == ssjBevel
    check element.strokeWidth == 4
    check element.strokeSegments.len == 2
    check element.strokeSegments[0].kind == sskQuadratic
    check element.strokeSegments[1].kind == sskQuadratic
