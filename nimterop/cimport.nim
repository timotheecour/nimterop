import macros, os, strformat, strutils

const CIMPORT {.used.} = 1

import "." / [globals,types,paths]
export types

proc interpPath(dir: string): string=
  # TODO: more robust: needs a DirSep after "$projpath"
  result = dir.replace("$projpath", getProjectPath())

proc joinPathIfRel(path1: string, path2: string): string =
  if path2.isAbsolute:
    result = path2
  else:
    result = joinPath(path1, path2)

proc findPath(path: string, fail = true): string =
  # Relative to project path
  result = joinPathIfRel(getProjectPath(), path).replace("\\", "/")
  if not fileExists(result) and not dirExists(result):
    doAssert (not fail), "File or directory not found: " & path
    result = ""

proc walkDirImpl(indir, inext: string, file=true): seq[string] =
  let
    dir = joinPathIfRel(getProjectPath(), indir)
    ext =
      if inext.len != 0:
        when not defined(Windows):
          "-name " & inext
        else:
          "\\" & inext
      else:
        ""

  let
    cmd =
      when defined(Windows):
        if file:
          "cmd /c dir /s/b/a-d " & dir.replace("/", "\\") & ext
        else:
          "cmd /c dir /s/b/ad " & dir.replace("/", "\\")
      else:
        if file:
          "find $1 -type f $2" % [dir, ext]
        else:
          "find $1 -type d" % dir

    (output, ret) = gorgeEx(cmd)

  if ret == 0:
    result = output.splitLines()

proc getFileDate(fullpath: string): string =
  var
    ret = 0
    cmd =
      when defined(Windows):
        &"cmd /c for %a in ({fullpath.quoteShell}) do echo %~ta"
      elif defined(Linux):
        &"stat -c %y {fullpath.quoteShell}"
      elif defined(OSX):
        &"stat -f %m {fullpath.quoteShell}"

  (result, ret) = gorgeEx(cmd)

  doAssert ret == 0, "File date error: " & fullpath & "\n" & result

proc getCacheValue(fullpath: string): string =
  if not gStateCT.nocache:
    result = fullpath.getFileDate()

proc getToastError(output: string): string =
  # Filter out preprocessor errors
  for line in output.splitLines():
    if "fatal error:" in line.toLowerAscii:
      result &= "\nERROR:$1\n" % line.split("fatal error:")[1]

  # Toast error
  if result.len == 0:
    result = output

proc getToastExe(): string =
  # TODO: also allow user override (via -d:nimteropToast:path or
  # see https://github.com/genotrance/nimterop/issues/68)
  result = toastExePath()
  #[
  todo:
  use same algo as shown here https://github.com/genotrance/nimterop/issues/69
  but using nim deps instead of c deps; they can be obtained via:
  `nim genDepend/--genDeps` or `https://github.com/nim-lang/RFCs/issues/123`
  ]#
  if not fileExists(result) or gStateCT.nocache:
    let toastSrc = nimteropSrcDir() / "toast.nim"
    let cmd = &"nim c -o:{result.quoteShell} {toastSrc.quoteShell}"
    when nimvm:
      echo ("getToastExe", cmd)
      let (output, ret) = gorgeEx(cmd, cache=getCacheValue(toastSrc))
      doAssert ret == 0, $(cmd, ret, toastSrc) & " output:\n" & output
    else:
      # todo: maybe support if it makes sense
      doAssert false # TODO
  else:
    discard # uses cached toast

proc getToast(fullpath: string, recurse: bool = false): string =
  var
    ret = 0
    cmd = when defined(Windows): "cmd /c " else: ""

  cmd &= &"{getToastExe()} --pnim --preprocess "

  if recurse:
    cmd.add "--recurse "

  for i in gStateCT.defines:
    cmd.add &"--defines+={i.quoteShell} "

  for i in gStateCT.includeDirs:
    cmd.add &"--includeDirs+={i.quoteShell} "

  if gStateCT.symOverride.len != 0:
    cmd.add &"--symOverride={gStateCT.symOverride.join(\",\")} "

  cmd.add &"{fullpath.quoteShell}"
  echo cmd
  # see https://github.com/genotrance/nimterop/issues/69
  (result, ret) = gorgeEx(cmd, cache=getCacheValue(fullpath))
  doAssert ret == 0, getToastError(result)

proc getGccPaths(mode = "c"): string =
  var
    ret = 0
    nul = when defined(Windows): "nul" else: "/dev/null"
    mmode = if mode == "cpp": "c++" else: mode

  (result, ret) = gorgeEx("gcc -Wp,-v -x" & mmode & " " & nul)

macro cOverride*(body): untyped =
  ## When the wrapper code generated by nimterop is missing certain symbols or not
  ## accurate, it may be required to hand wrap them. Define them in a
  ## `cOverride() <cimport.html#cOverride.m,>`_ macro block so that Nimterop no
  ## longer defines these symbols.
  ##
  ## For example:
  ##
  ## .. code-block:: c
  ##
  ##    int svGetCallerInfo(const char** fileName, int *lineNumber);
  ##
  ## This could get mapped to:
  ##
  ## .. code-block:: nim
  ##
  ##    proc svGetCallerInfo(fileName: ptr cstring; lineNumber: var cint)
  ##
  ## Whereas it might mean:
  ##
  ## .. code-block:: nim
  ##
  ##    cOverride:
  ##      proc svGetCallerInfo(fileName: var cstring; lineNumber: var cint)
  ##
  ## Using the `cOverride() <cimport.html#cOverride.m,>`_ block, nimterop
  ## can be instructed to skip over ``svGetCallerInfo()``. This works for procs,
  ## consts and types.

  for sym in body:
    case sym.kind:
      of nnkProcDef:
        gStateCT.symOverride.add ($sym[0]).strip(chars={'*'})
      of nnkConstSection, nnkTypeSection:
        for ssym in sym:
          gStateCT.symOverride.add ($ssym[0]).strip(chars={'*'})
      else:
        discard

  result = body

  if gStateCT.debug:
    echo "Overriding " & gStateCT.symOverride.join(" ")

macro cSkipSymbol*(skips: varargs[string]): untyped =
  ## Similar to `cOverride() <cimport.html#cOverride.m,>`_, this macro allows
  ## filtering out symbols not of interest from the generated output.
  ##
  ## .. code-block:: nim
  ##
  ##    cSkipSymbol "proc1", "Type2"

  for skip in skips:
    gStateCT.symOverride.add skip.strVal

proc cSearchPath*(path: string): string {.compileTime.}=
  ## Get full path to file or directory ``path`` in search path configured
  ## using `cAddSearchDir() <cimport.html#cAddSearchDir.m,>`_ and
  ## `cAddStdDir() <cimport.html#cAddStdDir.m,string>`_.
  ##
  ## This can be used to locate files or directories that can be passed onto
  ## `cCompile() <cimport.html#cCompile.m,,string>`_,
  ## `cIncludeDir() <cimport.html#cIncludeDir.m,>`_ and
  ## `cImport() <cimport.html#cImport.m,>`_.

  result = findPath(path, fail = false)
  if result.len == 0:
    var found = false
    for inc in gStateCT.searchDirs:
      result = (inc & "/" & path).replace("\\", "/")
      if fileExists(result) or dirExists(result):
        found = true
        break
    doAssert found, "File or directory not found: " & path &
      " gStateCT.searchDirs: " & $gStateCT.searchDirs

macro cDebug*(): untyped =
  ## Enable debug messages and display the generated Nim code

  gStateCT.debug = true

macro cDisableCaching*(): untyped =
  ## Disable caching of generated Nim code - useful during wrapper development
  ##
  ## If files included by header being processed by `cImport() <cimport.html#cImport.m,>`_
  ## change and affect the generated content, they will be ignored and the cached
  ## value will continue to be used . Use `cDisableCaching() <cimport.html#cDisableCaching.m,>`_
  ## to avoid this scenario during development.
  ##
  ## ``nim -f`` was broken prior to 0.19.4 but can also be used to flush the cached content.

  gStateCT.nocache = true

macro cDefine*(name: static string, val: static string = ""): untyped =
  ## ``#define`` an identifer that is forwarded to the C/C++ compiler
  ## using ``{.passC: "-DXXX".}``

  result = newNimNode(nnkStmtList)

  var str = name
  if val.nBl:
    str &= &"={val.quoteShell}"

  if str notin gStateCT.defines:
    gStateCT.defines.add(str)
    str = "-D" & str

    result.add(quote do:
      {.passC: `str`.}
    )

    if gStateCT.debug:
      echo result.repr

macro cAddSearchDir*(dir: static string): untyped =
  ## Add directory ``dir`` to the search path used in calls to
  ## `cSearchPath() <cimport.html#cSearchPath,string>`_.
  ##
  ## This allows something like this:
  ##
  ## .. code-block:: nim
  ##
  ##    cAddSearchDir("path/to/includes")
  ##    cImport cSearchPath("file.h")

  var dir = interpPath(dir)
  if dir notin gStateCT.searchDirs:
    gStateCT.searchDirs.add(dir)

macro cIncludeDir*(dir: static string): untyped =
  ## Add an include directory that is forwarded to the C/C++ compiler
  ## using ``{.passC: "-IXXX".}``. This is also provided to the
  ## preprocessor during Nim code generation.

  var dir = interpPath(dir)
  result = newNimNode(nnkStmtList)

  let
    fullpath = findPath(dir)
    str = &"-I{fullpath.quoteShell}"

  if fullpath notin gStateCT.includeDirs:
    gStateCT.includeDirs.add(fullpath)

    result.add(quote do:
      {.passC: `str`.}
    )

  if gStateCT.debug:
    echo result.repr

macro cAddStdDir*(mode = "c"): untyped =
  ## Add the standard ``c`` [default] or ``cpp`` include paths to search
  ## path used in calls to `cSearchPath() <cimport.html#cSearchPath,string>`_
  ##
  ## This allows something like this:
  ##
  ## .. code-block:: nim
  ##
  ##    cAddStdDir()
  ##    cImport cSearchPath("math.h")

  result = newNimNode(nnkStmtList)

  var
    inc = false

  for line in getGccPaths(mode.strVal()).splitLines():
    if "#include <...> search starts here" in line:
      inc = true
      continue
    elif "End of search list" in line:
      break

    if inc:
      let sline = line.strip()
      result.add quote do:
        cAddSearchDir(`sline`)

macro cCompile*(path: static string, mode = "c"): untyped =
  ## Compile and link C/C++ implementation into resulting binary using ``{.compile.}``
  ##
  ## ``path`` can be a specific file or contain wildcards:
  ##
  ## .. code-block:: nim
  ##
  ##     cCompile("file.c")
  ##     cCompile("path/to/*.c")
  ##
  ## ``mode`` recursively searches for code files in ``path``.
  ##
  ## ``c`` searches for ``*.c`` whereas ``cpp`` searches for ``*.C *.cpp *.c++ *.cc *.cxx``
  ##
  ## .. code-block:: nim
  ##
  ##    cCompile("path/to/dir", "cpp")

  result = newNimNode(nnkStmtList)

  var
    stmt = ""

  proc fcompile(file: string): string =
    let fn = file.splitFile().name
    var
      ufn = fn
      uniq = 1
    while ufn in gStateCT.compile:
      ufn = fn & $uniq
      uniq += 1

    gStateCT.compile.add(ufn)
    if fn == ufn:
      #[
      # todo: use quoteShell everywhere relevant; adding `"` is not always correct and also read uglier eg:
      {.passC: "-I\"/Users/foo/include\"".}
      whereas quoteShell would, here, give simply
      {.passC: "-I/Users/foo/include".}
      ]#
      return "{.compile: \"$#\".}" % file.replace("\\", "/")
    else:
      return "{.compile: (\"../$#\", \"$#.o\").}" % [file.replace("\\", "/"), ufn]

  proc dcompile(dir: string, ext=""): string =
    let
      files = walkDirImpl(dir, ext)

    for f in files:
      if f.len != 0:
        result &= fcompile(f) & "\n"

  if path.contains("*") or path.contains("?"):
    stmt &= dcompile(path)
  else:
    let fpath = findPath(path)
    if fileExists(fpath):
      stmt &= fcompile(fpath) & "\n"
    elif dirExists(fpath):
      if mode.strVal().contains("cpp"):
        for i in @["*.C", "*.cpp", "*.c++", "*.cc", "*.cxx"]:
          stmt &= dcompile(fpath, i)
      else:
        stmt &= dcompile(fpath, "*.c")

  result.add stmt.parseStmt()

  if gStateCT.debug:
    echo result.repr

macro cImport*(filename: static string, recurse: static bool = false): untyped =
  ## Import all supported definitions from specified header file. Generated
  ## content is cached in ``nimcache`` until ``filename`` changes unless
  ## `cDisableCaching() <cimport.html#cDisableCaching.m,>`_ is set. ``nim -f``
  ## can also be used after Nim v0.19.4 to flush the cache.
  ##
  ## ``recurse`` can be used to generate Nim wrappers from ``#include`` files
  ## referenced in ``filename``. This is only done for files in the same
  ## directory as ``filename`` or in a directory added using
  ## `cIncludeDir() <cimport.html#cIncludeDir.m,>`_

  result = newNimNode(nnkStmtList)

  let
    fullpath = findPath(filename)

  echo "Importing " & fullpath

  let
    output = getToast(fullpath, recurse)

  try:
    result.add parseStmt(output)
  except:
    echo output
    echo "Failed to import generated nim"
    result.add parseStmt(output)

  if gStateCT.debug:
    echo result.repr
