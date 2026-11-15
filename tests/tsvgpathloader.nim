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

  test "resolves inline properties and skips invisible geometry":
    let document = parseSvgDocument(
      """
<svg width="20" height="20" color="red">
  <rect width="0" height="4"/>
  <g display="none"><rect display="inline" width="2" height="2"/></g>
  <rect width="4" height="4" fill="blue" style="fill: currentColor; fill-opacity: 0.5; stroke: none; stroke-width: 3"/>
</svg>
"""
    )
    check document.elements.len == 1
    check document.elements[0].fillColor.r == 1
    check document.elements[0].fillColor.a == 0.5
    check not document.elements[0].hasStroke

  test "supports fractional view boxes and opacity groups":
    let document = parseSvgDocument(
      """
<svg viewBox='1.5,2.25,10.5,12.5'><g opacity='0.5'>
  <rect x='1.5' y='2.25' width='2' height='3' opacity='0.25'/>
  <rect x='4' y='2' width='1' height='1'/>
</g></svg>
"""
    )
    check document.width == 11
    check document.height == 13
    check document.elements[0].fillPath.computeBounds() == rect(0, 0, 2, 3)
    check document.elements[0].opacityGroupStarts == @[0.5'f32, 0.25'f32]
    check document.elements[0].opacityGroupEnds == 1
    check document.elements[1].opacityGroupEnds == 1
    check document.elements[0].fillColor.a == 1

  test "expands use references and normalizes invalid colors":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 20 20'><defs><symbol id='shape'>
  <rect width='2' height='3' fill='rgb(255,0,0)'/>
</symbol></defs><use href='#shape' x='4' y='5' transform='scale(2)'/></svg>
"""
    )
    check document.elements.len == 1
    check document.elements[0].fillPath.computeBounds() == rect(8, 10, 4, 6)
    check document.elements[0].fillColor.r == 1
    expect PixieError:
      discard parseSvgDocument(
        "<svg viewBox='0 0 1 1'><path d='M0 0' fill='nonsense'/></svg>"
      )

  test "maps symbol viewBox into use viewport":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 20.5 10.25'><defs>
  <symbol id='s' viewBox='1 2 4 2'><rect x='1' y='2' width='4' height='2'/></symbol>
  <symbol id='n' viewBox='1 2 4 2' preserveAspectRatio='none'><rect x='1' y='2' width='4' height='2'/></symbol>
</defs><use href='#s' width='8' height='8'/><use href='#n' width='8' height='8'/></svg>
"""
    )
    check document.viewportSize == vec2(20.5, 10.25)
    check document.elements[0].fillPath.computeBounds() == rect(0, 2, 8, 4)
    check document.elements[1].fillPath.computeBounds() == rect(0, 0, 8, 8)

  test "exposes local ellipse width and paint opacities":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 20 20'><ellipse cx='5' cy='5' rx='3' ry='2'
  fill='url(#g)' fill-opacity='.3' stroke='url(#g)' stroke-opacity='.4' stroke-width='2'/></svg>
"""
    )
    check document.elements[0].primitiveStrokeWidth == 2
    check document.elements[0].fillOpacity == 0.3'f32
    check document.elements[0].strokeOpacity == 0.4'f32
    check document.elements[0].strokePath != nil

  test "rejects cyclic use references":
    expect PixieError:
      discard parseSvgDocument(
        """
<svg viewBox='0 0 1 1'><defs><g id='a'><use href='#b'/></g>
<g id='b'><use href='#a'/></g></defs><use href='#a'/></svg>
"""
      )

  test "inherited currentColor follows each child's color":
    let document = parseSvgDocument(
      """
<svg viewBox='0 0 20 20'><g color='red' fill='currentColor' stroke='currentColor'>
<rect width='4' height='4' color='blue' stroke-width='1'/>
<rect x='5' width='4' height='4' color='lime' stroke-width='1'/>
<rect x='10' width='4' height='4' stroke-width='1'/>
</g></svg>
"""
    )
    check document.elements[0].fillColor.b == 1
    check document.elements[0].strokeColor.b == 1
    check document.elements[0].strokePaintValue == "blue"
    check document.elements[1].fillColor.g == 1
    check document.elements[1].strokeColor.g == 1
    check document.elements[2].fillColor.r == 1
    check document.elements[2].strokeColor.r == 1
