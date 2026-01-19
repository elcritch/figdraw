import std/[asynchttpserver, asyncdispatch, os, osproc, strformat, strutils,
    times, uri]

type ServerOpts = object
  port: Port
  autoBuild: bool
  forceBuild: bool

const
  baseDir = "examples/emscripten"
  defaultHtml = "opengl_windy_renderlist_webgl.html"
  entryNim = "examples/opengl_windy_renderlist_webgl.nim"
  outJs = baseDir / "opengl_windy_renderlist_webgl.js"
  outWasm = baseDir / "opengl_windy_renderlist_webgl.wasm"

proc guessMimeType(path: string): string {.gcsafe.} =
  let ext = path.splitFile.ext.toLowerAscii()
  case ext
  of ".html": "text/html; charset=utf-8"
  of ".js": "text/javascript; charset=utf-8"
  of ".wasm": "application/wasm"
  of ".data": "application/octet-stream"
  of ".json": "application/json; charset=utf-8"
  of ".map": "application/json; charset=utf-8"
  of ".css": "text/css; charset=utf-8"
  of ".png": "image/png"
  of ".jpg", ".jpeg": "image/jpeg"
  of ".gif": "image/gif"
  of ".svg": "image/svg+xml"
  else: "application/octet-stream"

proc safeJoin(baseDir, urlPath: string): string {.gcsafe.} =
  let baseAbs = baseDir.expandFilename()
  var rel = urlPath
  if rel.startsWith("/"):
    rel = rel[1 ..^ 1]

  # `decodeUrl` is safe here; we still block traversal after expanding.
  rel = decodeUrl(rel)

  let full = (baseAbs / rel).expandFilename()
  if full == baseAbs:
    return full
  if not full.startsWith(baseAbs & DirSep):
    raise newException(ValueError, "path traversal blocked")
  full

proc respondText(req: Request, code: HttpCode, text: string) {.async, gcsafe.} =
  let headers = newHttpHeaders({
    "Content-Type": "text/plain; charset=utf-8",
    "Cache-Control": "no-store",
  })
  await req.respond(code, text, headers)

proc serveFile(req: Request, filePath: string) {.async, gcsafe.} =
  if not fileExists(filePath):
    await respondText(req, Http404, "404 not found: " & filePath & "\n")
    return

  let headers = newHttpHeaders({
    "Content-Type": guessMimeType(filePath),
    "Cache-Control": "no-store",
    "Cross-Origin-Opener-Policy": "same-origin",
    "Cross-Origin-Embedder-Policy": "require-corp",
  })

  # `readFile` returns a string of bytes; ok for `.wasm`/`.data` too.
  await req.respond(Http200, readFile(filePath), headers)

proc outputsPresent(): bool =
  fileExists(outJs) and fileExists(outWasm)

proc outputsStale(): bool =
  if not outputsPresent():
    return true
  try:
    let srcTime = entryNim.getLastModificationTime()
    let jsTime = outJs.getLastModificationTime()
    let wasmTime = outWasm.getLastModificationTime()
    result = jsTime < srcTime or wasmTime < srcTime
  except OSError:
    result = true

proc hasTool(name: string): bool =
  findExe(name).len > 0

proc buildEmscriptenBundle(force: bool): bool =
  if not force and not outputsStale():
    return true

  if not hasTool("nim"):
    echo "Missing `nim` on PATH."
    return false

  if not hasTool("emcc"):
    echo "Missing `emcc` (Emscripten). Install/activate it, then re-run."
    echo "Expected outputs: ", outJs, " and ", outWasm
    return false

  var args = @["buildWebGL"]
  if force:
    args = @["-d:figdrawForceWebGLBuild", "buildWebGL"]

  let cmd = quoteShellCommand(@["nim"] & args)
  echo "Building emscripten bundle..."
  echo "  ", cmd

  let procRes = execCmdEx(cmd)
  if procRes.exitCode != 0:
    echo procRes.output
    echo "Build failed (exit code ", procRes.exitCode, ")."
    return false

  if not outputsPresent():
    echo procRes.output
    echo "Build finished, but outputs were not found:"
    echo "  ", outJs
    echo "  ", outWasm
    return false

  true

proc parseArgs(): ServerOpts =
  result.port = Port(8000)
  result.autoBuild = true
  result.forceBuild = false

  for i in 1 .. paramCount():
    let a = paramStr(i)
    if a.len == 0:
      continue
    if a == "--":
      continue
    if a == "--no-build":
      result.autoBuild = false
    elif a == "--build":
      result.autoBuild = true
    elif a == "--force":
      result.autoBuild = true
      result.forceBuild = true
    elif a.startsWith("--port="):
      result.port = Port(parseInt(a.split("=", 1)[1]))
    elif a.allCharsInSet({'0'..'9'}):
      result.port = Port(parseInt(a))
    else:
      echo "Unknown arg: ", a
      echo "Usage: emscripten_static_server [port] [--build] [--force] [--no-build] [--port=8000]"
      quit(2)

when isMainModule:
  let opts = parseArgs()
  if opts.autoBuild:
    if not buildEmscriptenBundle(opts.forceBuild):
      quit(1)

  var port = Port(8000)
  port = opts.port

  let server = newAsyncHttpServer()
  echo &"Serving `{baseDir}` on http://127.0.0.1:{port.int}/"
  echo &"Open: http://127.0.0.1:{port.int}/{defaultHtml}"

  let cb = proc(req: Request): Future[void] {.closure, async, gcsafe.} =
    if req.reqMethod != HttpGet:
      await respondText(req, Http405, "405 method not allowed\n")
      return

    var path = req.url.path
    if path.len == 0 or path == "/":
      path = "/" & defaultHtml

    try:
      let fullPath = safeJoin(baseDir, path)
      await serveFile(req, fullPath)
    except ValueError:
      await respondText(req, Http400, "400 bad request\n")

  waitFor server.serve(port, cb)
