when defined(feature.figdraw.vulkan) or defined(vk14Prototype):
  import std/unittest
  import pkg/vk14/[commands, enums, types]
  import figdraw/vulkan/vk14_prototype

  var
    requestedVersions: seq[uint32]
    reportedVersion: uint32
    rejectFirst: bool
    createStatus: VkResult
    sawExtension: bool

  proc mockVersion(version: ptr uint32): VkResult {.stdcall.} =
    version[] = reportedVersion
    VK_SUCCESS

  proc mockCreate(
      info: ptr VkInstanceCreateInfo,
      allocator: ptr VkAllocationCallbacks,
      instance: ptr VkInstance,
  ): VkResult {.stdcall.} =
    requestedVersions.add(info.pApplicationInfo.apiVersion)
    sawExtension =
      info.enabledExtensionCount == 1 and
      $info.ppEnabledExtensionNames[0] == "VK_KHR_surface"
    if rejectFirst and requestedVersions.len == 1:
      return VK_ERROR_INCOMPATIBLE_DRIVER
    if createStatus == VK_SUCCESS:
      instance[] = VkInstance(42)
    createStatus

  suite "vk14 prototype instance bootstrap":
    setup:
      requestedVersions = @[]
      reportedVersion = VK_API_VERSION_1_4
      rejectFirst = false
      createStatus = VK_SUCCESS
      sawExtension = false

    test "uses Vulkan 1.1 and passes requested extensions":
      let dispatch = PrototypeDispatch(
        vkCreateInstance: mockCreate, vkEnumerateInstanceVersion: mockVersion
      )
      let instance = dispatch.createInstance([cstring "VK_KHR_surface"])
      check int64(instance) == 42
      check requestedVersions == @[VK_API_VERSION_1_1]
      check sawExtension

    test "falls back to 1.0 after an incompatible driver":
      rejectFirst = true
      let dispatch = PrototypeDispatch(
        vkCreateInstance: mockCreate, vkEnumerateInstanceVersion: mockVersion
      )
      discard dispatch.createInstance()
      check requestedVersions == @[VK_API_VERSION_1_1, VK_API_VERSION_1_0]

    test "a 1.0 loader does not need version enumeration":
      let dispatch = PrototypeDispatch(vkCreateInstance: mockCreate)
      discard dispatch.createInstance()
      check requestedVersions == @[VK_API_VERSION_1_0]

    test "other errors do not trigger a retry":
      createStatus = VK_ERROR_OUT_OF_HOST_MEMORY
      let dispatch = PrototypeDispatch(
        vkCreateInstance: mockCreate, vkEnumerateInstanceVersion: mockVersion
      )
      expect PrototypeError:
        discard dispatch.createInstance()
      check requestedVersions == @[VK_API_VERSION_1_1]

    test "dispatch is per context and does not change vk14 globals":
      let original = commands.vkCreateInstance
      let first = PrototypeDispatch(vkCreateInstance: mockCreate)
      let second = PrototypeDispatch()
      discard first.createInstance()
      check second.vkCreateInstance == nil
      check commands.vkCreateInstance == original

    when defined(vk14PrototypeRuntime):
      test "creates and destroys instances through the real loader":
        let first = newPrototypeDispatch()
        let second = newPrototypeDispatch()
        let firstInstance = first.createInstance()
        first.loadInstance(firstInstance)
        let secondInstance = second.createInstance()
        second.loadInstance(secondInstance)
        check first.vkDestroyInstance != nil
        check second.vkDestroyInstance != nil
        check first.vkEnumeratePhysicalDevices != nil
        var count: uint32
        check first.vkEnumeratePhysicalDevices(firstInstance, count.addr, nil) ==
          VK_SUCCESS
        check count > 0
        second.vkDestroyInstance(secondInstance, nil)
        first.vkDestroyInstance(firstInstance, nil)
