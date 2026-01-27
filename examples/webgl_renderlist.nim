when not defined(js) and not defined(nimsuggest):
  {.fatal: "This example requires the Nim JS backend (nim js).".}

import std/[dom, jsconsole, jsffi]
import chroma

import figdraw/commons
import figdraw/fignodes
import figdraw/opengl/renderer as glrenderer
import figdraw/opengl/glapi
import figdraw/utils/glutils
import figdraw/webgl/api as webgl

proc makeRenderTree*(w, h: float32): Renders =
  var list = RenderList()

  let rootIdx = list.addRoot(Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(0, 0, w, h),
    fill: rgba(255, 255, 255, 255).color,
  ))

  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    corners: [10.0'f32, 20.0, 30.0, 40.0],
    screenBox: rect(60, 60, 220, 140),
    fill: rgba(220, 40, 40, 255).color,
    stroke: RenderStroke(weight: 5.0, color: rgba(0, 0, 0, 255).color)
  ))
  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(320, 120, 220, 140),
    fill: rgba(40, 180, 90, 255).color,
    shadows: [
      RenderShadow(
        style: DropShadow,
        blur: 10,
        spread: 10,
        x: 10,
        y: 10,
        color: rgba(0, 0, 0, 55).color,
    ),
    RenderShadow(),
    RenderShadow(),
    RenderShadow(),
  ],
  ))
  list.addChild(rootIdx, Fig(
    kind: nkRectangle,
    childCount: 0,
    zlevel: 0.ZLevel,
    screenBox: rect(180, 300, 220, 140),
    fill: rgba(60, 90, 220, 255).color,
  ))

  result = Renders(layers: initOrderedTable[ZLevel, RenderList]())
  result.layers[0.ZLevel] = list

proc main() =
  app.running = true
  app.autoUiScale = false
  app.uiScale = 1.0

  let canvas = webgl.asCanvas(document.createElement("canvas"))
  document.body.appendChild(canvas)

  document.body.style.margin = "0"
  document.body.style.overflow = "hidden"
  document.body.style.background = "#0c0f16"
  canvas.style.display = "block"

  let gl = cast[glapi.WebGL2RenderingContext](canvas.getContext("webgl2"))
  if gl.isNull or gl.isUndefined:
    console.error("WebGL2 not available")
    return

  setWebGLContext(gl)
  startOpenGL(openglVersion)

  let renderer = glrenderer.newOpenGLRenderer(
    atlasSize = 192,
    pixelScale = 1.0,
  )

  var lastCssSize = vec2(0.0'f32, 0.0'f32)
  var renders = makeRenderTree(0.0'f32, 0.0'f32)

  proc resizeAndRender() =
    let dpr = if window.devicePixelRatio <= 0: 1.0 else: window.devicePixelRatio
    let cssWidth = max(window.innerWidth, 1)
    let cssHeight = max(window.innerHeight, 1)

    app.pixelScale = dpr.float32
    renderer.ctx.pixelScale = app.pixelScale

    canvas.width = int(cssWidth.float * dpr)
    canvas.height = int(cssHeight.float * dpr)
    canvas.style.width = cstring($cssWidth & "px")
    canvas.style.height = cstring($cssHeight & "px")

    let cssSize = vec2(cssWidth.float32, cssHeight.float32)
    if cssSize != lastCssSize:
      lastCssSize = cssSize
      renders = makeRenderTree(cssSize.x, cssSize.y)

    renderer.renderFrame(
      renders,
      vec2(canvas.width.float32, canvas.height.float32),
    )

  proc onResize(e: Event) =
    resizeAndRender()

  window.addEventListener("resize", onResize)
  resizeAndRender()

when isMainModule:
  main()
