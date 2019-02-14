# avoids clashes between installed and local version of each module
switch("path", ".")

#[
see D20190127T231316 workaround for fact that toast needs to build
scanner.cc, which would otherwise result in link errors such as:
"std::terminate()", referenced from:
      ___clang_call_terminate in scanner.cc.o
]#
when defined(MacOSX):
  switch("clang.linkerexe", "g++")
else:
  switch("gcc.linkerexe", "g++")

# Workaround for NilAccessError crash on Windows #98
when defined(Windows):
  switch("gc", "markAndSweep")

const workaround_10629 = defined(windows) and defined(nimdoc)
when workaround_10629:
  import ospaths
  import strformat

  proc getNimRootDir(): string =
    fmt"{currentSourcePath}".parentDir.parentDir.parentDir

  const file = getNimRootDir() / "lib/pure/ospaths.nim"
  echo ("PRTEMP:", file)
  const dir = getTempDir()
  const file2 = dir / "ospaths.nim"
  var text = file.readFile
  import strutils
  text = replace(text, """
    DirSep* = '/'""", """
    DirSep* = '\\'""")

  writeFile file2, text
  patchFile("stdlib", "ospaths", file2)
