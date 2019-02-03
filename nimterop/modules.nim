##[
Module that imports everything so that `nim doc --project` runs docs
on everything.
]##

when true:
  ## pending https://github.com/nim-lang/Nim/pull/10527
  import sequtils, os, strformat, macros
  import "."/[paths]
  macro importPaths(a: static openArray[string]): untyped =
    result = newStmtList()
    for ai in a: result.add quote do: from `ai` import nil

  const dir = nimteropSrcDir()
  const files = block:
    var ret: seq[string]
    for path in walkDirRec(dir, yieldFilter = {pcFile}):
      if path.splitFile.ext != ".nim": continue
      if path.splitFile.name in ["astold"]: continue
      if path == currentSourcePath: continue
      #[
      using `relativePath` because some files in nimterop use `import nimterop/foo`
      and it'd otherwise give this error:
Hint: tsgen [Processing]
modules.nim(24, 15) template/generic instantiation of `importPaths` from here
/Users/travis/.nimble/pkgs/nimterop-0.1.1/nimterop/cimport.nim(1, 2) Error: module names need to be unique per Nimble package; module clashes with /Users/travis/build/nimterop/nimterop/nimterop/cimport.nim
      ]#
      ret.add path.relativePath nimteropRoot()
    ret
  static: echo files
  importPaths files
