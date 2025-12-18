## Quick benchmark: R3-R17 with malebolgia parallel search
##
## Run: nim c -r -d:release --threads:on tests/benchmark_r17_quick.nim

import std/[times, strformat, strutils, cpuinfo, json, os, monotimes]
import std/tables as stdtables
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/search/parallel


proc loadPrimesDataset(filename: string): (VariableList, coretable.Table) =
  let content = readFile(filename)
  let js = parseJson(content)

  var varList = initVariableList()
  for v in js["variables"]:
    discard varList.add(newVariable(
      v["name"].getStr(), v["abbrev"].getStr(),
      Cardinality(v["cardinality"].getInt()), v["isDependent"].getBool()
    ))

  var freqMap = stdtables.initTable[Key, float64]()
  for row in js["data"]:
    var k = newKey(varList.keySize)
    for i in 0..<row.len:
      k.setValue(varList, VariableIndex(i), row[i].getInt() - 1)
    freqMap.mgetOrPut(k, 0.0) += 1.0

  var tbl = coretable.initTable(varList.keySize, freqMap.len)
  for k, count in freqMap:
    tbl.add(k, count)
  tbl.sort()
  tbl.normalize()
  (varList, tbl)


proc main() =
  echo ""
  echo "=" .repeat(70)
  echo "R3-R17 PARALLEL SEARCH BENCHMARK (MALEBOLGIA)"
  echo "=" .repeat(70)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  let dataFile = "data/primes_R3_R17.json"
  if not fileExists(dataFile):
    echo "Dataset not found: ", dataFile
    quit(1)

  echo "Loading dataset..."
  let (varList, inputTable) = loadPrimesDataset(dataFile)
  echo "State space: ", inputTable.len
  echo ""

  var mgr = newVBManager(varList, inputTable)
  let startModel = mgr.bottomRefModel
  echo "Starting model: ", startModel.printName(varList)
  echo ""

  # Warm up
  discard parallelSearch(varList, inputTable, startModel, SearchLoopless,
                         SearchAIC, 3, 2, useParallel = false)

  echo "Width  Levels    Seq(ms)    Par(ms)   Speedup"
  echo "-" .repeat(50)

  for (width, levels) in [(3, 3), (5, 3), (5, 4), (7, 4)]:
    # Sequential (wall clock)
    let seqStart = getMonoTime()
    let seqResults = parallelSearch(varList, inputTable, startModel, SearchLoopless,
                                    SearchAIC, width, levels, useParallel = false)
    let seqMs = (getMonoTime() - seqStart).inMilliseconds.float64

    # Parallel (wall clock)
    let parStart = getMonoTime()
    let parResults = parallelSearch(varList, inputTable, startModel, SearchLoopless,
                                    SearchAIC, width, levels, useParallel = true)
    let parMs = (getMonoTime() - parStart).inMilliseconds.float64

    let speedup = seqMs / parMs
    let marker = if speedup > 1.1: " <<<" elif speedup > 1.0: " <" else: ""
    echo &"{width:>5} {levels:>7} {seqMs:>10.0f} {parMs:>10.0f} {speedup:>9.2f}x{marker}"

  echo ""


when isMainModule:
  main()
