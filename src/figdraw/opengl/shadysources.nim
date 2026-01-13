import pkg/shady
import pkg/vmath

const
  sdfModeAtlas = 0'i32
  sdfModeClipAA = 3'i32
  sdfModeDropShadow = 7'i32
  sdfModeDropShadowAA = 8'i32
  sdfModeInsetShadow = 9'i32
  sdfModeInsetShadowAnnular = 10'i32
  sdfModeAnnular = 11'i32
  sdfModeAnnularAA = 12'i32

proc sdRoundedBox(p: Vec2, b: Vec2, r: Vec4): float32 =
  ## Signed distance function for a rounded box.
  ## Ported from iquilezles.org (MIT license).
  ## `r` corner radii order: (top-right, bottom-right, top-left, bottom-left).
  var rr: float32
  if p.x > 0.0'f32:
    if p.y > 0.0'f32:
      rr = r.x
    else:
      rr = r.y
  else:
    if p.y > 0.0'f32:
      rr = r.z
    else:
      rr = r.w

  let q = abs(p) - b + vec2(rr, rr)
  result = min(max(q.x, q.y), 0.0'f32) + length(max(q, vec2(0.0'f32))) - rr

proc clamp01(x: float32): float32 =
  min(max(x, 0.0'f32), 1.0'f32)

proc clamp(x: float32, a: float32, b: float32): float32 =
  min(max(x, a), b)

proc smoothstep(edge0: float32, edge1: float32, x: float32): float32 =
  var t: float32
  t = clamp01((x - edge0) / (edge1 - edge0))
  result = t * t * (3.0'f32 - 2.0'f32 * t)

proc gaussian(x: float32, s: float32): float32 =
  ## Matches sdfy `drawSdfShape` gaussian kernel.
  1.0'f32 / (s * sqrt(6.283185307179586'f32)) *
    exp(-1.0'f32 * (x * x) / (2.0'f32 * s * s))

proc atlasVertMain(
    gl_Position: var Vec4,
    proj: Uniform[Mat4],
    vertexPos: Vec2,
    vertexUv: Vec2,
    vertexColor: Vec4,
    pos: var Vec2,
    uv: var Vec2,
    color: var Vec4,
) =
  pos = vertexPos
  uv = vertexUv
  color = vertexColor
  gl_Position = proj * vec4(vertexPos.x, vertexPos.y, 0.0'f32, 1.0'f32)

proc atlasFragMain(
    fragColor: var Vec4,
    windowFrame: Uniform[Vec2],
    atlasTex: Uniform[Sampler2D],
    maskTex: Uniform[Sampler2D],
    pos: Vec2,
    uv: Vec2,
    color: Vec4,
) =
  let tex = texture(atlasTex, uv)
  fragColor = vec4(
    tex.x * color.x,
    tex.y * color.y,
    tex.z * color.z,
    tex.w * color.w,
  )

  let normalizedPos = vec2(pos.x / windowFrame.x, 1.0'f32 - pos.y / windowFrame.y)
  fragColor.w = fragColor.w * texture(maskTex, normalizedPos).x

proc maskFragMain(
    fragColor: var Vec4,
    windowFrame: Uniform[Vec2],
    atlasTex: Uniform[Sampler2D],
    maskTex: Uniform[Sampler2D],
    pos: Vec2,
    uv: Vec2,
    color: Vec4,
) =
  let alpha = texture(atlasTex, uv).w * color.w
  fragColor = vec4(alpha, alpha, alpha, alpha)

  let normalizedPos = vec2(pos.x / windowFrame.x, 1.0'f32 - pos.y / windowFrame.y)
  fragColor.w = fragColor.w * texture(maskTex, normalizedPos).x

proc sdfRoundedBoxVertMain(
    gl_Position: var Vec4,
    proj: Uniform[Mat4],
    vertexPos: Vec2,
    vertexUv: Vec2,
    vertexColor: Vec4,
    vertexSdfParams: Vec4,
    vertexSdfRadii: Vec4,
    vertexSdfMode: uint32,
    vertexSdfFactors: Vec2,
    pos: var Vec2,
    uv: var Vec2,
    color: var Vec4,
    sdfParams: var Vec4,
    sdfRadii: var Vec4,
    sdfMode: var float32,
    sdfFactors: var Vec2,
) =
  pos = vertexPos
  uv = vertexUv
  color = vertexColor
  sdfParams = vertexSdfParams
  sdfRadii = vertexSdfRadii
  sdfMode = vertexSdfMode.float32
  sdfFactors = vertexSdfFactors
  gl_Position = proj * vec4(vertexPos.x, vertexPos.y, 0.0'f32, 1.0'f32)

proc sdfRoundedBoxFragMain(
    fragColor: var Vec4,
    windowFrame: Uniform[Vec2],
    atlasTex: Uniform[Sampler2D],
    maskTex: Uniform[Sampler2D],
    aaFactor: Uniform[float32],
    pos: Vec2,
    uv: Vec2,
    color: Vec4,
    sdfParams: Vec4,
    sdfRadii: Vec4,
    sdfMode: float32,
    sdfFactors: Vec2,
) =
  let quadHalfExtents = sdfParams.xy
  let shapeHalfExtents = sdfParams.zw

  # uv is (0..1, 0..1) in the quad's local space, y-down.
  let p = vec2(
    (uv.x - 0.5'f32) * 2.0'f32 * quadHalfExtents.x,
    (uv.y - 0.5'f32) * 2.0'f32 * quadHalfExtents.y,
  )

  # Select corner radii with y-down coordinates by flipping y for the SDF eval.
  let dist = sdRoundedBox(vec2(p.x, -p.y), shapeHalfExtents, sdfRadii)

  # Match sdfy `drawSdfShape` behavior for these modes:
  # - sdfModeClipAA: clamp(aaFactor * sd + 0.5)
  # - sdfModeAnnular: sd = abs(sd + factor) - factor
  # - sdfModeAnnularAA: same as Annular, but AA-mixed
  let sdfFactor = sdfFactors.x
  let sdfSpread = sdfFactors.y
  let sdfModeInt = int32(sdfMode)

  var alpha: float32 = 0.0'f32
  if sdfModeInt == sdfModeAtlas:
    let tex = texture(atlasTex, uv)
    fragColor = vec4(
      tex.x * color.x,
      tex.y * color.y,
      tex.z * color.z,
      tex.w * color.w,
    )
  else:
    let stdDevFactor = 1.0'f32 / 2.2'f32
    case sdfModeInt
    of sdfModeAnnular:
      let f = sdfFactor * 0.5'f32
      let sd = abs(dist + f) - f
      alpha = (if sd < 0.0'f32: 1.0'f32 else: 0.0'f32)
    of sdfModeAnnularAA:
      let f = sdfFactor * 0.5'f32
      let sd = abs(dist + f) - f
      let cl = clamp(aaFactor * sd + 0.5'f32, 0.0'f32, 1.0'f32)
      alpha = 1.0'f32 - cl
    of sdfModeDropShadow:
      let sd = dist - sdfSpread + 1.0'f32
      let x = sd / (sdfFactor + 0.5'f32)
      let a = 1.1'f32 * gaussian(x, stdDevFactor)
      alpha = (if sd > 0.0'f32: min(a, 1.0'f32) else: 1.0'f32)
    of sdfModeDropShadowAA:
      let cl = clamp(aaFactor * dist + 0.5'f32, 0.0'f32, 1.0'f32)
      let insideAlpha = 1.0'f32 - cl
      let sd = dist - sdfSpread + 1.0'f32
      let x = sd / (sdfFactor + 0.5'f32)
      let a = 1.1'f32 * gaussian(x, stdDevFactor)
      alpha = (if sd >= 0.0'f32: min(a, 1.0'f32) else: insideAlpha)
    of sdfModeInsetShadow:
      let sd = dist + sdfSpread + 1.0'f32
      let x = sd / (sdfFactor + 0.5'f32)
      let a = 1.1'f32 * gaussian(x, stdDevFactor)
      alpha = (if sd < 0.0'f32: min(a, 1.0'f32) else: 1.0'f32)
    of sdfModeInsetShadowAnnular:
      let sd = dist + sdfSpread + 1.0'f32
      let x = sd / (sdfFactor + 0.5'f32)
      let a = 1.1'f32 * gaussian(x, stdDevFactor)
      alpha = (if sd < 0.0'f32: min(a, 1.0'f32) else: 0.0'f32)
    else:
      # sdfModeClipAA (default)
      let cl = clamp(aaFactor * dist + 0.5'f32, 0.0'f32, 1.0'f32)
      alpha = 1.0'f32 - cl

    fragColor = vec4(color.x, color.y, color.z, color.w * alpha)

  let normalizedPos = vec2(pos.x / windowFrame.x, 1.0'f32 - pos.y / windowFrame.y)
  fragColor.w = fragColor.w * texture(maskTex, normalizedPos).x

const
  atlasVert330* = toGLSL(atlasVertMain, version = "330", extra = "")
  atlasFrag330* = toGLSL(atlasFragMain, version = "330", extra = "")
  maskFrag330* = toGLSL(maskFragMain, version = "330", extra = "")
  sdfRoundedBoxVert330* = toGLSL(sdfRoundedBoxVertMain, version = "330", extra = "")
  sdfRoundedBoxFrag330* = toGLSL(sdfRoundedBoxFragMain, version = "330", extra = "")

  atlasVert410* = toGLSL(atlasVertMain, version = "410", extra = "")
  atlasFrag410* = toGLSL(atlasFragMain, version = "410", extra = "")
  maskFrag410* = toGLSL(maskFragMain, version = "410", extra = "")
  sdfRoundedBoxVert410* = toGLSL(sdfRoundedBoxVertMain, version = "410", extra = "")
  sdfRoundedBoxFrag410* = toGLSL(sdfRoundedBoxFragMain, version = "410", extra = "")

  atlasVert3es* = toGLSL(atlasVertMain, version = "300 es", extra = "")
  atlasFrag3es* = toGLSL(atlasFragMain, version = "300 es", extra = "")
  maskFrag3es* = toGLSL(maskFragMain, version = "300 es", extra = "")
  sdfRoundedBoxVert3es* = toGLSL(sdfRoundedBoxVertMain, version = "300 es", extra = "")
  sdfRoundedBoxFrag3es* = toGLSL(sdfRoundedBoxFragMain, version = "300 es", extra = "")
