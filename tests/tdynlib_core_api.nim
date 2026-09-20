import std/unittest

import figdraw

suite "core API":
  test "excludes windowing symbols":
    doAssert declared(Fig)
    doAssert not declared(Window)
    doAssert not declared(KeyEvent)
    doAssert not declared(SiwinRenderer)
    doAssert not declared(newSiwinWindow)
