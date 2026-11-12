# Pixie's path flattener is private. Keep its implementation in its own module so
# its internal Path type does not leak into the public SVG API.
include pixie/paths

proc flattenSvgPath*(data: string): seq[Polygon] =
  let path = parsePath(data)
  var shapesOut: seq[Polygon]
  var at, start: Vec2
  var chunk = newPath()
  var hasSegment = false
  proc flush() =
    if hasSegment:
      let shapes = chunk.commandsToShapes(false, 4)
      if shapes.len == 0:
        shapesOut.add @[start]
      else:
        shapesOut.add shapes
    chunk = newPath()
    chunk.moveTo(at.x, at.y)
    start = at
    hasSegment = false

  var i = 0
  while i < path.commands.len:
    let kind = path.commands[i].PathCommandKind
    let count = kind.parameterCount()
    let j = i + 1
    if kind in {Move, RMove}:
      flush()
      let p = vec2(path.commands[j], path.commands[j + 1])
      at =
        if kind == Move:
          p
        else:
          at + p
      start = at
      chunk = newPath()
      chunk.moveTo(at.x, at.y)
    else:
      chunk.commands.add path.commands[i .. i + count]
      hasSegment = hasSegment or kind != Close
      case kind
      of Line, TQuad, RLine, RTQuad:
        let p = vec2(path.commands[j], path.commands[j + 1])
        at =
          if kind in {RLine, RTQuad}:
            at + p
          else:
            p
      of HLine:
        at.x = path.commands[j]
      of VLine:
        at.y = path.commands[j]
      of RHLine:
        at.x += path.commands[j]
      of RVLine:
        at.y += path.commands[j]
      of Cubic, SCubic, Quad, Arc, RCubic, RSCubic, RQuad, RArc:
        let p = vec2(path.commands[j + count - 2], path.commands[j + count - 1])
        at =
          if kind in {RCubic, RSCubic, RQuad, RArc}:
            at + p
          else:
            p
      of Close:
        at = start
        flush()
      of Move, RMove:
        discard
    i += count + 1
  flush()
  result = shapesOut
