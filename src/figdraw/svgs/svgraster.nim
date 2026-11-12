## Raster compositing for SVG opacity groups and gradient paints.

import std/[math, strutils, tables, xmltree]
import pkg/pixie
import ./[svgpathloader, svgstrokes]

type Surface = object
  image, tint: Image
  opacity: float32
  group: ParsedSvgCompositeGroup
  first: int

proc matrix(a: SvgAffine): Mat3 =
  result = mat3()
  result[0, 0] = a.a
  result[0, 1] = a.b
  result[1, 0] = a.c
  result[1, 1] = a.d
  result[2, 0] = a.tx
  result[2, 1] = a.ty

proc collectIds(node: XmlNode, ids: var Table[string, XmlNode]) =
  if node.kind == xnElement:
    if node.attr("id").len > 0:
      ids[node.attr("id")] = node
    for child in node:
      child.collectIds(ids)

proc value(node: XmlNode, name, default: string): string =
  result = node.attr(name)
  if result.len == 0:
    result = default

proc number(value: string): float32 =
  if value.endsWith("%"):
    parseFloat(value[0 .. ^2]).float32 / 100
  else:
    parseFloat(value).float32

proc styleValue(node: XmlNode, name, default: string): string =
  result = node.value(name, default)
  for part in node.attr("style").split(';'):
    let colon = part.find(':')
    if colon >= 0 and part[0 ..< colon].strip() == name:
      result = part[colon + 1 .. ^1].strip()

proc gradientTransform(value: string): Mat3 =
  result = mat3()
  var remaining = value.strip()
  while remaining.len > 0:
    let opening = remaining.find('(')
    let closing = remaining.find(')')
    if opening < 0 or closing < opening:
      raise newException(PixieError, "Invalid gradient transform")
    let kind = remaining[0 ..< opening].strip()
    let args = remaining[opening + 1 ..< closing].replace(',', ' ').splitWhitespace()
    var values: seq[float32]
    for arg in args:
      values.add number(arg)
    var transform = mat3()
    case kind
    of "matrix":
      if values.len != 6:
        raise newException(PixieError, "Invalid gradient matrix")
      transform[0, 0] = values[0]
      transform[0, 1] = values[1]
      transform[1, 0] = values[2]
      transform[1, 1] = values[3]
      transform[2, 0] = values[4]
      transform[2, 1] = values[5]
    of "translate":
      if values.len notin 1 .. 2:
        raise newException(PixieError, "Invalid gradient translation")
      transform = translate(
        vec2(
          values[0],
          if values.len == 2:
            values[1]
          else:
            0,
        )
      )
    of "scale":
      if values.len notin 1 .. 2:
        raise newException(PixieError, "Invalid gradient scale")
      transform = scale(
        vec2(
          values[0],
          if values.len == 2:
            values[1]
          else:
            values[0],
        )
      )
    of "rotate":
      if values.len != 1 and values.len != 3:
        raise newException(PixieError, "Invalid gradient rotation")
      let center =
        if values.len == 3:
          vec2(values[1], values[2])
        else:
          vec2(0, 0)
      transform =
        translate(center) * rotate(values[0] * PI.float32 / 180) * translate(-center)
    else:
      raise newException(PixieError, "Unsupported gradient transform: " & kind)
    result = result * transform
    remaining = remaining[closing + 1 .. ^1].strip()

proc coordinateValue(value: string, extent, origin: float32, userSpace: bool): float32 =
  result = value.number()
  if userSpace and value.endsWith("%"):
    result = origin + result * extent

proc gradient(
    node: XmlNode,
    element: ParsedSvgElement,
    pixelMatrix: Mat3,
    viewport: Rect,
    opacity: float32,
    tint: bool,
): Paint =
  if node.tag notin ["linearGradient", "radialGradient"]:
    raise newException(PixieError, "SVG paint reference is not a gradient")
  if node.attr("href").len > 0 or node.attr("xlink:href").len > 0:
    raise newException(PixieError, "SVG gradient references are not supported")
  if node.attr("spreadMethod") notin ["", "pad"]:
    raise newException(PixieError, "SVG gradient spread method is not supported")
  let units = node.value("gradientUnits", "objectBoundingBox")
  var coordinate = pixelMatrix * element.sourceTransform.matrix()
  if units == "objectBoundingBox":
    let bounds = element.strokePath.computeBounds()
    coordinate = coordinate * translate(bounds.xy) * scale(bounds.wh)
  elif units != "userSpaceOnUse":
    raise newException(PixieError, "Invalid gradient units")
  coordinate = coordinate * gradientTransform(node.attr("gradientTransform"))
  let userSpace = units == "userSpaceOnUse"
  template xvalue(key, default: string): float32 =
    coordinateValue(node.value(key, default), viewport.w, viewport.x, userSpace)

  template yvalue(key, default: string): float32 =
    coordinateValue(node.value(key, default), viewport.h, viewport.y, userSpace)

  if node.tag == "linearGradient":
    result = newPaint(LinearGradientPaint)
    result.gradientHandlePositions = @[
      coordinate * vec2(xvalue("x1", "0%"), yvalue("y1", "0%")),
      coordinate * vec2(xvalue("x2", "100%"), yvalue("y2", "0%")),
    ]
  else:
    let cx = xvalue("cx", "50%")
    let cy = yvalue("cy", "50%")
    let radius = coordinateValue(
      node.value("r", "50%"),
      sqrt((viewport.w * viewport.w + viewport.h * viewport.h) / 2),
      0,
      userSpace,
    )
    if xvalue("fx", $cx) != cx or yvalue("fy", $cy) != cy:
      raise
        newException(PixieError, "SVG radial gradient focal points are not supported")
    result = newPaint(RadialGradientPaint)
    result.gradientHandlePositions = @[
      coordinate * vec2(cx, cy),
      coordinate * vec2(cx + radius, cy),
      coordinate * vec2(cx, cy + radius),
    ]
  result.opacity = opacity
  for child in node:
    if child.kind == xnElement and child.tag == "stop":
      var stopColor = parseHtmlColor(child.styleValue("stop-color", "black"))
      stopColor.a *= clamp(number(child.styleValue("stop-opacity", "1")), 0, 1)
      if tint:
        stopColor = color(1, 1, 1, stopColor.a)
      let position = clamp(number(child.value("offset", "0")), 0, 1)
      result.gradientStops.add colorStop(stopColor, position)
  if result.gradientStops.len == 0:
    raise newException(PixieError, "SVG gradient has no stops")

proc paintFor(
    element: ParsedSvgElement,
    fill, tint: bool,
    ids: Table[string, XmlNode],
    pixelMatrix: Mat3,
    viewport: Rect,
): Paint =
  let paintValue = if fill: element.fillPaintValue else: element.strokePaintValue
  if paintValue.startsWith("url(#") and paintValue.endsWith(")"):
    let id = paintValue[5 .. ^2]
    if id notin ids:
      raise newException(PixieError, "Missing SVG gradient: " & id)
    let opacity = if fill: element.fillOpacity else: element.strokeOpacity
    result = gradient(ids[id], element, pixelMatrix, viewport, opacity, tint)
  else:
    var c = if fill: element.fillColor else: element.strokeColor
    if tint:
      c = color(1, 1, 1, c.a)
    result = newPaint(SolidPaint)
    result.color = c

proc rasterizeSvgElements*(
  document: ParsedSvgDocument, first, last: int, longEdge: Positive
): tuple[image, tintImage: Image, frame: Rect]

proc referenceMask(
    document: ParsedSvgDocument,
    bounds: Rect,
    groupTransform: SvgAffine,
    definition: XmlNode,
    sourceTransform: SvgAffine,
    isClip: bool,
    longEdge: Positive,
    width, height: int,
): Image =
  let expected = if isClip: "clipPath" else: "mask"
  if definition.tag != expected:
    raise newException(PixieError, "SVG reference is not a " & expected)
  let units =
    if isClip:
      definition.value("clipPathUnits", "userSpaceOnUse")
    else:
      definition.value("maskContentUnits", "userSpaceOnUse")
  var transform = sourceTransform.matrix()
  if units == "objectBoundingBox":
    transform = groupTransform.matrix() * translate(bounds.xy) * scale(bounds.wh)
  elif units != "userSpaceOnUse":
    raise newException(PixieError, "Unsupported SVG " & expected & " units")
  if not isClip and (
    definition.attr("x").len > 0 or definition.attr("y").len > 0 or
    definition.attr("width").len > 0 or definition.attr("height").len > 0
  ):
    raise newException(PixieError, "Explicit SVG mask regions are not supported")
  var defs, content: string
  for node in document.root:
    if node.kind == xnElement and node.tag == "defs":
      defs.add $node
  for node in definition:
    content.add $node
  let a = transform
  let transformText =
    "matrix(" & $a[0, 0] & " " & $a[0, 1] & " " & $a[1, 0] & " " & $a[1, 1] & " " &
    $a[2, 0] & " " & $a[2, 1] & ")"
  let svg =
    "<svg viewBox='0 0 " & $document.viewportSize.x & " " & $document.viewportSize.y &
    "'>" & defs & "<g transform='" & transformText & "'>" & content & "</g></svg>"
  let maskDocument = parseSvgDocument(svg)
  if maskDocument.elements.len == 0:
    return newImage(width, height)
  for child in maskDocument.elements:
    for group in child.compositeGroupStarts:
      if group.clipPathIds.len > 0 or group.maskIds.len > 0:
        raise
          newException(PixieError, "Nested SVG clip paths and masks are not supported")
  let rendered =
    rasterizeSvgElements(maskDocument, 0, maskDocument.elements.high, longEdge)
  result = if isClip: rendered.tintImage else: rendered.image
  if not isClip and definition.value("mask-type", "luminance") != "alpha":
    for pixel in result.data.mitems:
      let alpha = uint8(
        clamp(
          int(
            round(
              pixel.r.float32 * 0.2126'f32 + pixel.g.float32 * 0.7152'f32 +
                pixel.b.float32 * 0.0722'f32
            )
          ),
          0,
          255,
        )
      )
      pixel = rgbx(alpha, alpha, alpha, alpha)

proc groupBounds(
    document: ParsedSvgDocument, first, last: int, transform: SvgAffine
): Rect =
  let m = transform.matrix()
  let determinant = transform.a * transform.d - transform.b * transform.c
  if determinant.classify in {fcNan, fcInf, fcNegInf} or abs(determinant) < 1e-20:
    raise newException(PixieError, "Singular SVG compositing transform")
  let inverse = m.inverse()
  var initialized = false
  for index in first .. last:
    let element = document.elements[index]
    if not element.strokePath.isNil:
      let path = element.strokePath.copy()
      path.transform(inverse * element.sourceTransform.matrix())
      let b = path.computeBounds()
      if not initialized:
        result = b
        initialized = true
      else:
        let x = min(result.x, b.x)
        let y = min(result.y, b.y)
        let right = max(result.x + result.w, b.x + b.w)
        let bottom = max(result.y + result.h, b.y + b.h)
        result = rect(x, y, right - x, bottom - y)

proc rasterizeSvgElements*(
    document: ParsedSvgDocument, first, last: int, longEdge: Positive
): tuple[image, tintImage: Image, frame: Rect] =
  try:
    if first < 0 or last >= document.elements.len or first > last:
      raise newException(PixieError, "Invalid SVG element range")
    let size = document.viewportSize
    let resolution = min(4096'f32, max(longEdge.float32, max(size.x, size.y)))
    let factor = resolution / max(size.x, size.y)
    let width = max(1, int(ceil(size.x * factor)))
    let height = max(1, int(ceil(size.y * factor)))
    let pixelMatrix = scale(vec2(factor, factor))
    let box = document.root.attr("viewBox").replace(',', ' ').splitWhitespace()
    let viewport =
      if box.len == 4:
        rect(number(box[0]), number(box[1]), size.x, size.y)
      else:
        rect(0, 0, size.x, size.y)
    result.frame = rect(0, 0, width.float32 / factor, height.float32 / factor)
    var ids: Table[string, XmlNode]
    document.root.collectIds(ids)
    var stack = @[
      Surface(image: newImage(width, height), tint: newImage(width, height), opacity: 1)
    ]
    for i in first .. last:
      let element = document.elements[i]
      for group in element.compositeGroupStarts:
        stack.add Surface(
          image: newImage(width, height),
          tint: newImage(width, height),
          opacity: group.opacity,
          group: group,
          first: i,
        )
      if element.hasFill:
        stack[^1].image.fillPath(
          element.fillPath,
          element.paintFor(true, false, ids, pixelMatrix, viewport),
          pixelMatrix,
          element.fillRule,
        )
        stack[^1].tint.fillPath(
          element.fillPath,
          element.paintFor(true, true, ids, pixelMatrix, viewport),
          pixelMatrix,
          element.fillRule,
        )
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
        let transform = pixelMatrix * element.sourceTransform.matrix()
        stack[^1].image.fillPath(
          outline, element.paintFor(false, false, ids, pixelMatrix, viewport), transform
        )
        stack[^1].tint.fillPath(
          outline, element.paintFor(false, true, ids, pixelMatrix, viewport), transform
        )
      for j in 0 ..< element.compositeGroupEnds:
        if stack.len < 2:
          raise newException(PixieError, "Unbalanced SVG compositing group")
        let child = stack.pop()
        let group = child.group
        let bounds = document.groupBounds(child.first, i, group.sourceTransform)
        for index, id in group.clipPathIds:
          if id notin ids:
            raise newException(PixieError, "Missing SVG clip path: " & id)
          let mask = referenceMask(
            document,
            bounds,
            group.sourceTransform,
            ids[id],
            group.clipPathTransforms[index],
            true,
            longEdge,
            width,
            height,
          )
          child.image.draw(mask, blendMode = MaskBlend)
          child.tint.draw(mask, blendMode = MaskBlend)
        for index, id in group.maskIds:
          if id notin ids:
            raise newException(PixieError, "Missing SVG mask: " & id)
          let mask = referenceMask(
            document,
            bounds,
            group.sourceTransform,
            ids[id],
            group.maskTransforms[index],
            false,
            longEdge,
            width,
            height,
          )
          child.image.draw(mask, blendMode = MaskBlend)
          child.tint.draw(mask, blendMode = MaskBlend)
        child.image.applyOpacity(child.opacity)
        child.tint.applyOpacity(child.opacity)
        stack[^1].image.draw(child.image)
        stack[^1].tint.draw(child.tint)
    if stack.len != 1:
      raise newException(PixieError, "Unbalanced SVG opacity group")
    result.image = stack[0].image
    result.tintImage = stack[0].tint
  except PixieError:
    raise
  except CatchableError as error:
    raise newException(PixieError, error.msg)
