import std/unittest
import figdraw/commons

when UseVulkanBackend and (
  defined(figdrawTestVulkanMissingLibrary) or defined(figdrawTestVulkanMissingSymbol)
):
  import std/strutils
  import figdraw/vulkan/vulkan_dispatch

  suite "Vulkan loader failures":
    test "loader errors are catchable and can be retried":
      for attempt in 0 .. 1:
        try:
          discard newVulkanDispatch()
          check false
        except LibraryError as exc:
          when defined(figdrawTestVulkanMissingLibrary):
            check "could not load:" in exc.msg
          else:
            check "lacks vkGetInstanceProcAddr" in exc.msg
