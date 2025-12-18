## Benchmark: taskpools vs std/threadpool vs sequential
##
## Compare the modern taskpools library against deprecated std/threadpool
##
## Run: nim c -r -d:release --threads:on tests/benchmark_taskpools.nim

import std/[times, strformat, strutils, cpuinfo, math]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/parallel/eval as oldParallel
import ../src/occam/parallel/eval_taskpools as tpParallel


proc makeTestVarList(n: int; cardinality: int): VariableList =
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc makeRandomTable(varList: VariableList; seed: int = 42): coretable.Table =
  var totalStates = 1
  for i in 0..<varList.len:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initTable(varList.keySize, totalStates)

  var rng = seed
  proc nextRand(): float64 =
    rng = (rng * 1103515245 + 12345) mod (1 shl 31)
    float64(rng) / float64(1 shl 31)

  var indices = newSeq[int](varList.len)
  var done = false
  while not done:
    var keyPairs: seq[(VariableIndex, int)]
    for i in 0..<varList.len:
      keyPairs.add((VariableIndex(i), indices[i]))
    let key = varList.buildKey(keyPairs)
    result.add(key, nextRand() + 0.1)

    var carry = true
    for i in 0..<varList.len:
      if carry:
        indices[i] += 1
        if indices[i] >= varList[VariableIndex(i)].cardinality.toInt:
          indices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  result.sort()
  result.normalize()


proc makeLooplessModels(varList: VariableList; count: int): seq[Model] =
  result = @[]
  let n = varList.len

  while result.len < count:
    for chainLen in 2..min(n-1, 5):
      var rels: seq[Relation]
      for i in 0..<chainLen:
        rels.add(initRelation(@[VariableIndex(i), VariableIndex(i+1)]))
      result.add(initModel(rels))
      if result.len >= count: return

    for starSize in 2..min(n-1, 4):
      var rels: seq[Relation]
      for i in 1..starSize:
        rels.add(initRelation(@[VariableIndex(0), VariableIndex(i)]))
      result.add(initModel(rels))
      if result.len >= count: return


proc main() =
  echo ""
  echo "=".repeat(90)
  echo "TASKPOOLS vs STD/THREADPOOL vs SEQUENTIAL"
  echo "=".repeat(90)
  echo ""
  echo "CPU cores: ", countProcessors()
  echo ""

  # Test configurations
  let configs = [
    (5, 3, 50),    # 243 states, 50 models
    (6, 3, 50),    # 729 states, 50 models
    (6, 4, 50),    # 4096 states, 50 models
    (7, 3, 50),    # 2187 states, 50 models
    (7, 4, 25),    # 16384 states, 25 models
    (8, 3, 25),    # 6561 states, 25 models
    (8, 4, 10),    # 65536 states, 10 models
  ]

  echo "Config               States  Models   Seq(ms)   OldPar(ms)  TaskPool(ms)  TP Speedup"
  echo "-".repeat(90)

  for (nvars, card, numModels) in configs:
    let stateSpace = card ^ nvars
    let varList = makeTestVarList(nvars, card)
    let inputTable = makeRandomTable(varList)
    let models = makeLooplessModels(varList, numModels)

    # Warm up
    var mgr = newVBManager(varList, inputTable)
    discard mgr.computeAIC(models[0])

    # Sequential
    let seqStart = cpuTime()
    for model in models:
      discard mgr.computeAIC(model)
    let seqMs = (cpuTime() - seqStart) * 1000.0

    # Old threadpool
    let oldStart = cpuTime()
    discard oldParallel.parallelComputeAIC(varList, inputTable, models)
    let oldMs = (cpuTime() - oldStart) * 1000.0

    # Taskpools
    let tpStart = cpuTime()
    discard tpParallel.parallelComputeAIC_TP(varList, inputTable, models)
    let tpMs = (cpuTime() - tpStart) * 1000.0

    let tpSpeedup = if tpMs > 0.1: seqMs / tpMs else: 0.0
    let marker = if tpSpeedup > 1.1: " <<<"
                 elif tpSpeedup > 1.0: " <"
                 else: ""

    let configStr = $nvars & "v x " & $card & "c"
    echo fmt"{configStr:<20} {stateSpace:>6}  {models.len:>6}   {seqMs:>8.1f}   {oldMs:>10.1f}  {tpMs:>12.1f}  {tpSpeedup:>9.2f}x{marker}"

  # Cleanup
  tpParallel.shutdownPool()

  echo ""
  echo "Legend: <<< = significant speedup (>1.1x), < = marginal speedup (>1.0x)"
  echo ""


when isMainModule:
  main()
