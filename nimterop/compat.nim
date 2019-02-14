#[
module for backward compatibility
put everything that requires `when (NimMajor, NimMinor, NimPatch)` here
]#

import std/strutils

const workaround_10629* = defined(windows) and defined(nimdoc)
  ## pending https://github.com/nim-lang/Nim/pull/10527

when workaround_10629:
  import std/os except parentDir, DirSep
else:
  import std/os
  export parentDir, DirSep

when workaround_10629:
  const DirSep* = '\\'
  proc parentDirPos(path: string): int =
    var q = 1
    if len(path) >= 1 and path[len(path)-1] in {DirSep, AltSep}: q = 2
    for i in countdown(len(path)-q, 0):
      if path[i] in {DirSep, AltSep}: return i
    result = -1

  proc parentDir*(path: string): string =
    let sepPos = parentDirPos(path)
    if sepPos >= 0:
      result = substr(path, 0, sepPos-1)
    else:
      result = ""


when (NimMajor, NimMinor, NimPatch) >= (0, 19, 9):
  export relativePath
else:
  proc relativePath*(file, base: string): string =
    ## naive version of `os.relativePath` ; remove after nim >= 0.19.9
    runnableExamples:
      import ospaths, unittest
      check:
        "/foo/bar/baz/log.txt".unixToNativePath.relativePath("/foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
        "foo/bar/baz/log.txt".unixToNativePath.relativePath("foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
    var base = base.normalizedPath
    var file = file.normalizedPath
    if not base.endsWith DirSep: base.add DirSep
    doAssert file.startsWith base
    result = file[base.len .. ^1]
