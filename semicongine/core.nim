import std/macros
import std/math
import std/os
import std/paths
import std/strutils
import std/strformat
import std/tables
import std/typetraits

const RESOURCEROOT {.hint[XDeclaredButNotUsed]: off.} = "resources"

include ./core/utils
include ./core/buildconfig
include ./core/vector
include ./core/matrix
