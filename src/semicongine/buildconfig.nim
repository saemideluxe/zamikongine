import std/compilesettings
import std/strutils
import std/logging
import std/os

const ENGINENAME = "semicongine"

# checks required build options:
static:
  assert querySetting(gc) == "orc", ENGINENAME & " requires --mm=orc"
  assert compileOption("threads"), ENGINENAME & " requires --threads=on"

  if defined(release):
    assert compileOption("app", "gui"), ENGINENAME & " requires --app=gui for release builds"

  if defined(linux):
    assert defined(VK_USE_PLATFORM_XLIB_KHR), ENGINENAME & " requires --d:VK_USE_PLATFORM_XLIB_KHR for linux builds"
  elif defined(windows):
    assert defined(VK_USE_PLATFORM_XLIB_KHR), ENGINENAME & " requires --d:VK_USE_PLATFORM_WIN32_KHR for windows builds"
  else:
    assert false, "trying to build on unsupported platform"

# build configuration
# =====================

# compile-time defines, usefull for build-dependent settings
# can be overriden with compiler flags, e.g. -d:Foo=42 -d:Bar=false
# pramas: {.intdefine.} {.strdefine.} {.booldefine.}

# root of where settings files will be searched
# must be relative (to the directory of the binary)
const DEBUG* = not defined(release)
const CONFIGROOT* {.strdefine.}: string = "."
assert not isAbsolute(CONFIGROOT)

const CONFIGEXTENSION* {.strdefine.}: string = "ini"

# by default enable hot-reload of runtime-configuration only in debug builds
const CONFIGHOTRELOAD* {.booldefine.}: bool = DEBUG

# milliseconds to wait between checks for settings hotreload
const CONFIGHOTRELOADINTERVAL* {.intdefine.}: int = 1000

# log level
const LOGLEVEL {.strdefine.}: string = (when DEBUG: "lvlAll" else: "lvlWarn")
const ENGINE_LOGLEVEL* = parseEnum[Level](LOGLEVEL)

const MODROOT* {.strdefine.}: string = "mods"
const BUNDLETYPE* {.strdefine.}: string = "Dir" # zip, exe