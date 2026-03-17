import std/unittest

import pkg/vulkan

import figdraw/vulkan/vresource

type
  TestBuffer = object
    device: VkDevice
    handle: VkBuffer

  TestImageView = object
    handle: VkImageView

var deallocLog: seq[string]

proc `=destroy`(buf: var TestBuffer) =
  if buf.device != VkDevice(0) or buf.handle != VkBuffer(0):
    deallocLog.add("buffer:" & $cast[uint](buf.device) & ":" & $cast[uint](buf.handle))
  buf.device = VkDevice(0)
  buf.handle = VkBuffer(0)

proc `=destroy`(view: var TestImageView) =
  if view.handle != VkImageView(0):
    deallocLog.add("view:" & $cast[uint](view.handle))
  view.handle = VkImageView(0)

suite "vulkan resource wrapper":
  setup:
    deallocLog.setLen(0)

  test "destroy runs when wrapper leaves scope":
    block:
      let res = initVResource(TestBuffer(device: VkDevice(17), handle: VkBuffer(23)))
      check res[].device == VkDevice(17)
      check res[].handle == VkBuffer(23)
      check res.isInitialized()

    check deallocLog == @["buffer:17:23"]

  test "release transfers ownership without cleanup":
    var res = initVResource(TestImageView(handle: VkImageView(41)))

    let view = res.release()
    check view.handle == VkImageView(41)
    check not res.isInitialized()

    res.reset()
    check deallocLog.len == 0

  test "reset destroys current value before replacement":
    var res = initVResource(TestBuffer(device: VkDevice(3), handle: VkBuffer(5)))

    res.reset(TestBuffer(device: VkDevice(7), handle: VkBuffer(11)))

    check deallocLog == @["buffer:3:5"]
    res.reset()
    check deallocLog == @["buffer:3:5", "buffer:7:11"]
