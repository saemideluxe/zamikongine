import std/sequtils
import ./platform/window

import ./vulkan/api
import ./vulkan/instance
import ./vulkan/device
import ./vulkan/physicaldevice
import ./vulkan/renderpass

import ./gpu_data
import ./entity
import ./renderer
import ./mesh
import ./events
import ./config
import ./math

type
  Input = object
    keyIsDown: set[Key]
    keyWasPressed: set[Key]
    keyWasReleased: set[Key]
    mouseIsDown: set[MouseButton]
    mouseWasPressed: set[MouseButton]
    mouseWasReleased: set[MouseButton]
    mousePosition: Vec2f
    eventsProcessed: uint64
    windowWasResized: bool
  Engine* = object
    running*: bool
    device: Device
    debugger: Debugger
    instance: Instance
    window: NativeWindow
    renderer: Renderer
    input: Input
    exitHandler: proc(engine: var Engine)
    resizeHandler: proc(engine: var Engine)
    eventHandler: proc(engine: var Engine, event: Event)


proc destroy*(engine: var Engine) =
  checkVkResult engine.device.vk.vkDeviceWaitIdle()
  engine.renderer.destroy()
  engine.device.destroy()
  if engine.debugger.messenger.valid:
    engine.debugger.destroy()
  engine.window.destroy()
  engine.instance.destroy()
  engine.running = false


proc initEngine*(
  applicationName: string,
  debug=DEBUG,
  exitHandler: proc(engine: var Engine) = nil,
  resizeHandler: proc(engine: var Engine) = nil,
  eventHandler: proc(engine: var Engine, event: Event) = nil
): Engine =
  result.running = true
  result.exitHandler = exitHandler
  result.resizeHandler = resizeHandler
  result.eventHandler = eventHandler
  result.window = createWindow(applicationName)

  var
    instanceExtensions: seq[string]
    enabledLayers: seq[string]

  if debug:
    instanceExtensions.add "VK_EXT_debug_utils"
    enabledLayers.add @["VK_LAYER_KHRONOS_validation", "VK_LAYER_MESA_overlay"]
  result.instance = result.window.createInstance(
    vulkanVersion=VK_MAKE_API_VERSION(0, 1, 3, 0),
    instanceExtensions=instanceExtensions,
    layers=enabledLayers,
  )
  if debug:
    result.debugger = result.instance.createDebugMessenger()
  # create devices
  let selectedPhysicalDevice = result.instance.getPhysicalDevices().filterBestGraphics()
  result.device = result.instance.createDevice(
    selectedPhysicalDevice,
    enabledLayers = @[],
    enabledExtensions = @[],
    selectedPhysicalDevice.filterForGraphicsPresentationQueues()
  )

proc setRenderer*(engine: var Engine, renderPass: RenderPass) =
  engine.renderer = engine.device.initRenderer(renderPass)

proc addScene*(engine: var Engine, scene: Entity, vertexInput: seq[ShaderAttribute], transformAttribute="") =
  assert transformAttribute in map(vertexInput, proc(a: ShaderAttribute): string = a.name)
  engine.renderer.setupDrawableBuffers(scene, vertexInput, transformAttribute=transformAttribute)

proc renderScene*(engine: var Engine, scene: Entity) =
  assert engine.renderer.valid
  if engine.running:
    engine.renderer.refreshMeshData(scene)
    engine.renderer.render(scene)

proc updateInputs*(engine: var Engine) =
  if not engine.running:
    return

  engine.input.keyWasPressed = {}
  engine.input.keyWasReleased = {}
  engine.input.mouseWasPressed = {}
  engine.input.mouseWasReleased = {}
  engine.input.windowWasResized = false

  var killed = false
  for event in engine.window.pendingEvents():
    inc engine.input.eventsProcessed
    if engine.eventHandler != nil:
      engine.eventHandler(engine, event)
    case event.eventType:
      of Quit:
        killed = true
      of ResizedWindow:
        engine.input.windowWasResized = true
      of KeyPressed:
        engine.input.keyWasPressed.incl event.key
        engine.input.keyIsDown.incl event.key
      of KeyReleased:
        engine.input.keyWasReleased.incl event.key
        engine.input.keyIsDown.excl event.key
      of MousePressed:
        engine.input.mouseWasPressed.incl event.button
        engine.input.mouseIsDown.incl event.button
      of MouseReleased:
        engine.input.mouseWasReleased.incl event.button
        engine.input.mouseIsDown.excl event.button
      of MouseMoved:
        engine.input.mousePosition = newVec2(float32(event.x), float32(event.y))
  if killed:
    engine.running = false
    if engine.exitHandler != nil:
      engine.exitHandler(engine)
  if engine.input.windowWasResized and engine.resizeHandler != nil:
    engine.resizeHandler(engine)

func keyIsDown*(engine: Engine, key: Key): auto = key in engine.input.keyIsDown
func keyWasPressed*(engine: Engine, key: Key): auto = key in engine.input.keyWasPressed
func keyWasReleased*(engine: Engine, key: Key): auto = key in engine.input.keyWasReleased
func mouseIsDown*(engine: Engine, button: MouseButton): auto = button in engine.input.mouseIsDown
func mouseWasPressed*(engine: Engine, button: MouseButton): auto = button in engine.input.mouseWasPressed
func mouseWasReleased*(engine: Engine, button: MouseButton): auto = button in engine.input.mouseWasReleased
func mousePosition*(engine: Engine): auto = engine.input.mousePosition
func eventsProcessed*(engine: Engine): auto = engine.input.eventsProcessed
func framesRendered*(engine: Engine): auto = engine.renderer.framesRendered
func gpuDevice*(engine: Engine): Device = engine.device
func getWindow*(engine: Engine): auto = engine.window
func windowWasResized*(engine: Engine): auto = engine.input.windowWasResized