import std/unittest

when defined(features.figdraw.uirelays):
  import figdraw
  import ../examples/software_scene

  suite "software demo scene cache":
    setup:
      let oldScale = figUiScale()
      setFigUiScale(1)
    teardown:
      setFigUiScale(oldScale)

    test "unchanged frames reuse their scene and glyph layout":
      var cache: SoftwareSceneCache
      let first = cache.softwareScene()
      for i in 0 ..< 5:
        check cache.softwareScene() == first

    test "resize and density changes rebuild the retained scene":
      var cache: SoftwareSceneCache
      let first = cache.softwareScene()
      let resized = cache.softwareScene(800, 600)
      check resized != first
      check cache.softwareScene(800, 600) == resized
      setFigUiScale(2)
      let retina = cache.softwareScene(800, 600)
      check retina != resized
      check cache.softwareScene(800, 600) == retina

    test "font cache resets invalidate retained typefaces":
      var cache: SoftwareSceneCache
      let first = cache.softwareScene()
      resetFontCache()
      check cache.softwareScene() != first
else:
  suite "software demo scene cache":
    test "requires Atlas uirelays feature":
      skip()
