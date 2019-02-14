#[
module for backward compatibility
put everything that requires `when (NimMajor, NimMinor, NimPatch)` here
]#

import std/strutils

const workaround_10629* = defined(windows) and defined(nimdoc) and false
  ## pending https://github.com/nim-lang/Nim/pull/10527

when workaround_10629:
  import std/os except parentDir, DirSep, `/`
  # from std/os import nil
  export os except parentDir, DirSep, `/`, relativePath

else:
  # from std/os import parentDir, DirSep, `/`
  # import std/os
  import std/os except relativePath
  # export parentDir, DirSep, `/`
  export os except relativePath

when workaround_10629:
  const DirSep* = '\\'
  # const DirSep* = when defined(windows): '\\' else: '/'

  proc `/`*(lhs, rhs: string): string =
    result = lhs & $DirSep & rhs

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
  export os.relativePath
else:
  # from std/os import unixToNativePath, normalizedPath
  proc relativePath*(file, base: string): string =
    ## naive version of `os.relativePath` ; remove after nim >= 0.19.9
    runnableExamples:
      import ospaths, unittest
      check:
        "/foo/bar/baz/log.txt".unixToNativePath.relativePath("/foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
        "foo/bar/baz/log.txt".unixToNativePath.relativePath("foo/bar".unixToNativePath) == "baz/log.txt".unixToNativePath
    var base2 = base.normalizedPath
    var file2 = file.normalizedPath
    if not base2.endsWith DirSep: base2.add DirSep
    doAssert file2.startsWith base2, $(file, base, file2, base2, $DirSep)
    result = file2[base2.len .. ^1]
