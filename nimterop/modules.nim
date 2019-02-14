##[
Module that imports everything so that `nim doc --project` runs docs
on everything.
]##

when true:
  ## pending https://github.com/nim-lang/Nim/pull/10527
  import sequtils, os, strformat, macros
  # using "."/ would give similar error as D20190208T153915
  import nimterop/[paths, compat]

  macro importPaths(a: static openArray[string]): untyped =
    result = newStmtList()
    for ai in a: result.add quote do: from `ai` import nil

  const dirRoot = nimteropRoot()
  const dir = nimteropSrcDir()
  const files = block:
    var blacklist = @["astold"]
    when defined(workaround_10629):
      # workaround causes issues with getTempDir becoming `\`
      blacklist.add "tsgen"

    var ret: seq[string]
    for path in walkDirRec(dir, yieldFilter = {pcFile}):
      if path.splitFile.ext != ".nim": continue
      if path.splitFile.name in blacklist: continue
      if path == currentSourcePath: continue
      #[
      note(D20190208T153915): using `relativePath` because some files in nimterop
      use `import nimterop/foo` and it'd otherwise give `module clashes` error
      ]#
      ret.add path.relativePath dirRoot
    ret
  static: echo files
  importPaths files
