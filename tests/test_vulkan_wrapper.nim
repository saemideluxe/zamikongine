import semicongine/vulkan
import semicongine/platform/window


when isMainModule:
  # print basic driver infos
  echo "Layers"
  for layer in getLayers():
    echo "  " & layer
  echo "Instance extensions"
  for extension in getInstanceExtensions():
    echo "  " & extension

  # create instance
  var instance = createInstance(
    vulkanVersion=VK_MAKE_API_VERSION(0, 1, 3, 0),
    instanceExtensions= @["VK_EXT_debug_utils"],
    layers= @["VK_LAYER_KHRONOS_validation"]
  )
  var debugger = instance.createDebugMessenger()

  # create surface
  var thewindow = createWindow("Test")
  var surface = instance.createSurface(thewindow)

  # diagnostic output
  echo "Devices"
  for device in instance.getPhysicalDevices():
    echo "  " & $device
    echo "  Extensions"
    for extension in device.getExtensions():
      echo "    " & $extension
    echo "  Queue families"
    for queueFamily in device.getQueueFamilies():
      echo "    " & $queueFamily
    echo "  Surface present modes"
    for mode in device.getSurfacePresentModes(surface):
      echo "    " & $mode
    echo "  Surface formats"
    for format in device.getSurfaceFormats(surface):
      echo "    " & $format

  # create devices
  var devices: seq[Device]
  for physicalDevice in instance.getPhysicalDevices():
    devices.add physicalDevice.createDevice([], [], physicalDevice.getQueueFamilies(surface).filterForGraphicsPresentationQueues())

  # cleanup
  surface.destroy()
  for device in devices.mitems:
    device.destroy()

  debugger.destroy()
  instance.destroy()