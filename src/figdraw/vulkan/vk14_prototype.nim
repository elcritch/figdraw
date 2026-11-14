## Experimental vk14 instance bootstrap. The renderer still uses its existing
## binding; this module exercises vk14 declarations without global dispatch.

import pkg/vk14/[commands, enums, types]
import ./vulkan_versions

const VulkanLibrary =
  when defined(windows):
    "vulkan-1.dll"
  elif defined(macosx):
    "libMoltenVK.dylib"
  else:
    "libvulkan.so.1"

proc getInstanceProcAddr(
  instance: VkInstance, name: cstring
): pointer {.stdcall, dynlib: VulkanLibrary, importc: "vkGetInstanceProcAddr".}

type
  PrototypeDispatch* = ref object
    vkCreateInstance*: typeof(commands.vkCreateInstance)
    vkEnumerateInstanceVersion*: typeof(commands.vkEnumerateInstanceVersion)
    vkDestroyInstance*: typeof(commands.vkDestroyInstance)
    vkEnumeratePhysicalDevices*: typeof(commands.vkEnumeratePhysicalDevices)

  PrototypeError* = object of CatchableError
    status*: VkResult

proc loadInstance*(dispatch: PrototypeDispatch, instance: VkInstance) =
  for name, entry in fieldPairs(dispatch[]):
    entry = cast[typeof(entry)](getInstanceProcAddr(instance, name.cstring))

proc newPrototypeDispatch*(): PrototypeDispatch =
  result = PrototypeDispatch()
  result.loadInstance(VkInstance(0))

proc loaderVersion*(dispatch: PrototypeDispatch): uint32 =
  result = VK_API_VERSION_1_0
  if dispatch.vkEnumerateInstanceVersion != nil:
    var version = result
    if dispatch.vkEnumerateInstanceVersion(version.addr) == VK_SUCCESS:
      result = version

proc createInstance*(
    dispatch: PrototypeDispatch,
    extensions: openArray[cstring] = [],
    layers: openArray[cstring] = [],
    pNext: pointer = nil,
): VkInstance =
  ## Mirrors FigDraw's 1.1, then 1.0 instance creation policy.
  if dispatch.vkCreateInstance == nil:
    raise newException(PrototypeError, "vkCreateInstance is unavailable")
  for apiVersion in instanceVersionAttempts(dispatch.loaderVersion()):
    var appInfo = VkApplicationInfo(
      sType: VK_STRUCTURE_TYPE_APPLICATION_INFO,
      pApplicationName: "figdraw-vulkan",
      applicationVersion: vkMakeApiVersion(0, 0, 1, 0),
      pEngineName: "figdraw",
      engineVersion: vkMakeApiVersion(0, 0, 1, 0),
      apiVersion: apiVersion,
    )
    var info = VkInstanceCreateInfo(
      sType: VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO,
      pNext: pNext,
      pApplicationInfo: appInfo.addr,
      enabledLayerCount: layers.len.uint32,
      ppEnabledLayerNames:
        if layers.len == 0:
          nil
        else:
          cast[cstringArray](layers[0].unsafeAddr),
      enabledExtensionCount: extensions.len.uint32,
      ppEnabledExtensionNames:
        if extensions.len == 0:
          nil
        else:
          cast[cstringArray](extensions[0].unsafeAddr),
    )
    let status = dispatch.vkCreateInstance(info.addr, nil, result.addr)
    if status == VK_SUCCESS:
      return
    if status != VK_ERROR_INCOMPATIBLE_DRIVER or apiVersion == VK_API_VERSION_1_0:
      raise
        (ref PrototypeError)(msg: "vkCreateInstance failed: " & $status, status: status)
