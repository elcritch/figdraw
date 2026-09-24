import std/[isolation, unittest]
import threading/smartptrs
import sigils/rchannels

import figdraw/common/[fonttypes, transfer]
import figdraw/fignodes
import figdraw/renderfragments

type RenderTransfer = object
  fragments: RenderFragments
  renders: Renders
  tree: RenderTree

proc retainAlias[T](value: T): T {.noinline.} =
  value

proc makeTransfer(): RenderTransfer =
  let source = initArrangementRunes("a🙂b")
  let owner = shareGlyphArrangement(
    GlyphArrangement(
      sourceRunes: source,
      runes: source,
      arrangedGlyphs: @[ArrangedGlyph(), ArrangedGlyph(), ArrangedGlyph()],
    )
  )
  result.fragments = newRenderFragments()
  let root = result.fragments.addRoot(0.ZLevel, Fig(kind: nkRectangle))
  var contents = RenderList()
  discard contents.addRoot(Fig(kind: nkRectangle))
  let fragment = result.fragments.attachChildFragment(0.ZLevel, root, 0, move contents)
  let cursor = result.fragments.fragmentRoots(fragment)[0]
  var nested = RenderList()
  discard
    nested.addRoot(Fig(kind: nkText, textLayout: owner.glyphArrangementView(1 .. 2)))
  discard result.fragments.attachChildFragment(cursor, 0, move nested)
  result.renders = result.fragments.materialize()
  result.tree = result.renders[0.ZLevel].toTree()

  # Releasing aliases before handoff must not leave render data registered in
  # the producer's ORC candidate buffer. All handles and cursors also expire
  # before this procedure returns its exclusively owned payload.
  var fragmentsAlias = retainAlias(result.fragments)
  var rendersAlias = retainAlias(result.renders)
  var treeAlias = retainAlias(result.tree)
  doAssert not fragmentsAlias.isNil
  doAssert not rendersAlias.isNil
  doAssert not treeAlias.isNil
  fragmentsAlias = nil
  rendersAlias = nil
  treeAlias = nil

proc releaseOnWorker(channel: RChan[RenderTransfer]) {.thread.} =
  let payload = channel.recv()
  doAssert payload.fragments.materialize()[0.ZLevel].nodes.len == 3
  doAssert payload.renders[0.ZLevel].nodes.len == 3
  let layout = payload.renders[0.ZLevel].nodes[2].textLayout
  doAssert layout.isGlyphView()
  doAssert layout.glyphCount() == 2
  doAssert layout.shared[].sourceRunes.bytes == "a🙂b"
  doAssert payload.tree.children.len == 1
  doAssert payload.tree.children[0].children[0].children.len == 1

suite "FigDraw render ownership":
  test "aliased fragments, glyph views and render trees can move between threads":
    for iteration in 0 ..< 16:
      let channel = newRChan[RenderTransfer](1)
      # Preload the channel so the finite worker never waits for readiness.
      channel.send(unsafeIsolate(makeTransfer()))
      var worker: Thread[RChan[RenderTransfer]]
      createThread(worker, releaseOnWorker, channel)
      joinThread(worker)
