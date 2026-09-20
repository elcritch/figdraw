import std/unittest

when defined(useNativeDynlib):
  import figdraw

suite "native dynlib render fragments":
  when defined(useNativeDynlib):
    test "keeps fragment state opaque and mutates it in the producer":
      doAssert not compiles(default(RenderFragments).value)
      doAssert not compiles(default(RenderFragmentHandle).value)
      doAssert not compiles(default(RenderCursor).value)

      let fragments = newRenderFragments()
      let root = fragments.addRoot(
        0.ZLevel, Fig(kind: nkRectangle, screenBox: rect(0, 0, 100, 100))
      )

      var contents = RenderList()
      discard contents.addRoot(Fig(kind: nkRectangle, screenBox: rect(10, 10, 20, 20)))
      let original = fragments.attachChildFragment(0.ZLevel, root, 0, move contents)

      check fragments.isValid(original)
      check fragments.handleStatus(original) == rfsValid
      check original.fragmentId() != 0
      check fragments.effectiveChildCount(0.ZLevel, root) == 1

      let cursors = fragments.fragmentRoots(original)
      check cursors.len == 1
      check cursors[0].zlevel == 0.ZLevel
      check cursors[0].index == 0.FigIdx
      check cursors[0].fragmentHandle() == original
      check fragments[cursors[0]].kind == nkRectangle
      check fragments[0.ZLevel].nodes.len == 1

      var
        levels: seq[ZLevel]
        roots: seq[RenderCursor]
      for lvl in fragments.levels():
        levels.add lvl
      for cursor in fragments.roots(0.ZLevel):
        roots.add cursor
      check levels == @[0.ZLevel]
      check roots.len == 1

      var children: seq[RenderCursor]
      for cursor in fragments.children(fragments.nodeCursor(0.ZLevel, root)):
        children.add cursor
      check children == cursors

      var replacement = RenderList()
      discard replacement.addRoot(Fig(kind: nkRectangle))
      discard replacement.addRoot(Fig(kind: nkRectangle))
      let updated = fragments.replaceFragment(original, move replacement)

      check not fragments.isValid(original)
      check fragments.isValid(updated)
      check updated.fragmentId() == original.fragmentId()
      check fragments.effectiveChildCount(0.ZLevel, root) == 2
      check fragments.materialize().len(0.ZLevel) == 3

    test "constructs image styles from ids and references":
      let
        id = imgId("native-image-style")
        customFill = fill(rgba(12, 34, 56, 255))
        fromId = imageStyle(id, customFill)
        fromRef = imageStyle(imageRef(id), customFill)

      check fromId.id == id
      check fromId.fill.color == customFill.color
      check fromRef.id == id
      check fromRef.fill.color == customFill.color
  else:
    test "requires useNativeDynlib":
      skip()
