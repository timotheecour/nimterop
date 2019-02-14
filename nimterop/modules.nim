##[
Module that imports everything so that `nim doc --project` runs docs
on everything.
]##

when true:
  ## pending https://github.com/nim-lang/Nim/pull/10527
  # import sequtils, os, strformat, macros
  import sequtils, strformat, macros
  # using "."/ would give similar error as D20190208T153915
  import nimterop/[paths, compat]
  macro importPaths(a: static openArray[string]): untyped =
    result = newStmtList()
    for ai in a: result.add quote do: from `ai` import nil

  const dirRoot = nimteropRoot()
  const dir = nimteropSrcDir()

  const files = block:
    var ret: seq[string]
    for path in walkDirRec(dir, yieldFilter = {pcFile}):
      if path.splitFile.ext != ".nim": continue
      if path.splitFile.name in ["astold"]: continue
      when workaround_10629:
        if path.splitFile.name == currentSourcePath.splitFile.name: continue
      else:
        if path == currentSourcePath: continue
      #[
      note(D20190208T153915): using `relativePath` because some files in nimterop use `import nimterop/foo` and it'd otherwise give this error:
Hint: tsgen [Processing]
modules.nim(24, 15) template/generic instantiation of `importPaths` from here
/Users/travis/.nimble/pkgs/nimterop-0.1.1/nimterop/cimport.nim(1, 2) Error: module names need to be unique per Nimble package; module clashes with /Users/travis/build/nimterop/nimterop/nimterop/cimport.nim
      ]#
      echo ("importPaths", path, path.relativePath(dirRoot), dirRoot)
      ret.add path.relativePath dirRoot
    ret
  static: echo files
  importPaths files
