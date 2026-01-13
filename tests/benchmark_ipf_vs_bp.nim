## Benchmark: IPF vs Belief Propagation
##
## Compares performance of Iterative Proportional Fitting (IPF)
## against Belief Propagation (BP) on Junction Trees for loopless models.
##
## Run with: nim c -r -d:release tests/benchmark_ipf_vs_bp.nim

import std/[times, monotimes, strformat, strutils, math, sequtils, algorithm]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/core/junction_tree
import ../src/occam/math/ipf
import ../src/occam/math/belief_propagation as bp
import ../src/occam/math/entropy


type
  BenchmarkResult = object
    name: string
    ipfTimeMs: float64
    bpTimeMs: float64
    ipfIterations: int
    speedup: float64
    entropyDiff: float64


proc makeTestVarList(n: int; cardinality = 2): VariableList =
  ## Create a test variable list with n variables of given cardinality
  result = initVariableList()
  for i in 0..<n:
    let name = $chr(ord('A') + i)
    discard result.add(newVariable(name, name, Cardinality(cardinality)))


proc generateRandomTable(varList: VariableList; seed: int = 42): coretable.Table =
  ## Generate random probability table with realistic sparsity
  var totalStates = 1
  for i in 0..<varList.len:
    totalStates *= varList[VariableIndex(i)].cardinality.toInt

  result = coretable.initContingencyTable(varList.keySize, totalStates)

  # Use simple LCG for reproducibility
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

    # Add with random probability (skip ~30% for sparsity)
    let prob = nextRand()
    if prob > 0.3:
      result.add(key, prob)

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


proc benchmarkModel(name: string; varList: VariableList; model: Model;
                    inputTable: coretable.Table; runs = 10): BenchmarkResult =
  ## Benchmark IPF vs BP on a model
  result.name = name

  # Build junction tree (one-time cost, not included in BP timing)
  let jtResult = buildJunctionTree(model, varList)
  if not jtResult.valid:
    echo fmt"  Junction tree construction failed for {name}"
    return

  # Warm up
  discard ipf.ipf(inputTable, model.relations, varList)
  discard bp.beliefPropagation(inputTable, jtResult.tree, varList)

  # Benchmark IPF (wall clock)
  var ipfTimes: seq[float64]
  var totalIpfIter = 0
  for _ in 0..<runs:
    let start = getMonoTime()
    let ipfResult = ipf.ipf(inputTable, model.relations, varList)
    let elapsed = float64(inNanoseconds(getMonoTime() - start)) / 1_000_000.0
    ipfTimes.add(elapsed)
    totalIpfIter += ipfResult.iterations

  # Benchmark BP (wall clock)
  var bpTimes: seq[float64]
  for _ in 0..<runs:
    let start = getMonoTime()
    discard bp.beliefPropagation(inputTable, jtResult.tree, varList)
    let elapsed = float64(inNanoseconds(getMonoTime() - start)) / 1_000_000.0
    bpTimes.add(elapsed)

  # Calculate median times
  ipfTimes.sort()
  bpTimes.sort()
  result.ipfTimeMs = ipfTimes[runs div 2]
  result.bpTimeMs = bpTimes[runs div 2]
  result.ipfIterations = totalIpfIter div runs

  if result.bpTimeMs > 0.001:
    result.speedup = result.ipfTimeMs / result.bpTimeMs
  else:
    result.speedup = 0.0

  # Verify numerical equivalence
  let ipfResult = ipf.ipf(inputTable, model.relations, varList)
  let bpResult = bp.beliefPropagation(inputTable, jtResult.tree, varList)
  let bpJoint = bp.computeJointFromBP(bpResult, jtResult.tree, varList)

  let ipfH = entropy(ipfResult.fitTable)
  let bpH = entropy(bpJoint)
  result.entropyDiff = abs(ipfH - bpH)


proc alignLeft(s: string; width: int): string =
  if s.len >= width: s else: s & ' '.repeat(width - s.len)

proc alignRight(s: string; width: int): string =
  if s.len >= width: s else: ' '.repeat(width - s.len) & s

proc printResults(results: seq[BenchmarkResult]) =
  echo ""
  echo '='.repeat(90)
  echo "BENCHMARK RESULTS: IPF vs Belief Propagation"
  echo '='.repeat(90)
  echo ""
  echo alignLeft("Model", 32) & alignRight("IPF (ms)", 12) & alignRight("BP (ms)", 12) &
       alignRight("Speedup", 10) & alignRight("IPF Iter", 10) & alignRight("H Diff", 14)
  echo '-'.repeat(90)

  for r in results:
    let speedupStr = if r.speedup > 0: fmt"{r.speedup:.2f}x" else: "N/A"
    let diffStr = if r.entropyDiff < 1e-10: "<1e-10" else: fmt"{r.entropyDiff:.2e}"
    echo alignLeft(r.name, 32) &
         alignRight(fmt"{r.ipfTimeMs:.3f}", 12) &
         alignRight(fmt"{r.bpTimeMs:.3f}", 12) &
         alignRight(speedupStr, 10) &
         alignRight($r.ipfIterations, 10) &
         alignRight(diffStr, 14)

  echo '-'.repeat(90)

  # Calculate averages
  var totalSpeedup = 0.0
  var validCount = 0
  for r in results:
    if r.speedup > 0:
      totalSpeedup += r.speedup
      validCount += 1

  if validCount > 0:
    echo fmt"Average speedup: {totalSpeedup / float64(validCount):.2f}x"
  echo ""


proc main() =
  echo "Generating test data and running benchmarks..."
  echo ""

  var results: seq[BenchmarkResult]

  # Chain models: AB:BC:CD:...
  block:
    echo "Chain models (AB:BC:CD:...)"
    for n in [3, 4, 5, 6]:
      let varList = makeTestVarList(n, 3)  # Ternary variables
      let inputTable = generateRandomTable(varList)

      var rels: seq[Relation]
      for i in 0..<(n-1):
        rels.add(initRelation(@[VariableIndex(i), VariableIndex(i+1)]))
      let model = initModel(rels)

      let name = fmt"Chain-{n}vars (AB:BC:...)"
      let r = benchmarkModel(name, varList, model, inputTable)
      results.add(r)
      echo fmt"  {name}: IPF={r.ipfTimeMs:.3f}ms, BP={r.bpTimeMs:.3f}ms, speedup={r.speedup:.2f}x"

  # Star models: AB:AC:AD:...
  block:
    echo ""
    echo "Star models (AB:AC:AD:...)"
    for n in [3, 4, 5, 6]:
      let varList = makeTestVarList(n, 3)
      let inputTable = generateRandomTable(varList)

      var rels: seq[Relation]
      for i in 1..<n:
        rels.add(initRelation(@[VariableIndex(0), VariableIndex(i)]))
      let model = initModel(rels)

      let name = fmt"Star-{n}vars (AB:AC:...)"
      let r = benchmarkModel(name, varList, model, inputTable)
      results.add(r)
      echo fmt"  {name}: IPF={r.ipfTimeMs:.3f}ms, BP={r.bpTimeMs:.3f}ms, speedup={r.speedup:.2f}x"

  # Tree models: ABC:BDE:EFG (branching)
  block:
    echo ""
    echo "Branching tree models"

    # 5-variable tree: AB:BC:BD
    block:
      let varList = makeTestVarList(4, 3)
      let inputTable = generateRandomTable(varList)
      let model = initModel(@[
        initRelation(@[VariableIndex(0), VariableIndex(1)]),
        initRelation(@[VariableIndex(1), VariableIndex(2)]),
        initRelation(@[VariableIndex(1), VariableIndex(3)])
      ])
      let name = "Tree-4vars (AB:BC:BD)"
      let r = benchmarkModel(name, varList, model, inputTable)
      results.add(r)
      echo fmt"  {name}: IPF={r.ipfTimeMs:.3f}ms, BP={r.bpTimeMs:.3f}ms, speedup={r.speedup:.2f}x"

    # 6-variable tree: AB:BC:CD:CE:EF
    block:
      let varList = makeTestVarList(6, 3)
      let inputTable = generateRandomTable(varList)
      let model = initModel(@[
        initRelation(@[VariableIndex(0), VariableIndex(1)]),
        initRelation(@[VariableIndex(1), VariableIndex(2)]),
        initRelation(@[VariableIndex(2), VariableIndex(3)]),
        initRelation(@[VariableIndex(2), VariableIndex(4)]),
        initRelation(@[VariableIndex(4), VariableIndex(5)])
      ])
      let name = "Tree-6vars (AB:BC:CD:CE:EF)"
      let r = benchmarkModel(name, varList, model, inputTable)
      results.add(r)
      echo fmt"  {name}: IPF={r.ipfTimeMs:.3f}ms, BP={r.bpTimeMs:.3f}ms, speedup={r.speedup:.2f}x"

  # Higher cardinality models
  block:
    echo ""
    echo "Higher cardinality models"
    for card in [4, 5, 6]:
      let varList = makeTestVarList(4, card)
      let inputTable = generateRandomTable(varList)
      let model = initModel(@[
        initRelation(@[VariableIndex(0), VariableIndex(1)]),
        initRelation(@[VariableIndex(1), VariableIndex(2)]),
        initRelation(@[VariableIndex(2), VariableIndex(3)])
      ])
      let name = fmt"Chain-4vars card={card}"
      let r = benchmarkModel(name, varList, model, inputTable)
      results.add(r)
      echo fmt"  {name}: IPF={r.ipfTimeMs:.3f}ms, BP={r.bpTimeMs:.3f}ms, speedup={r.speedup:.2f}x"

  # Larger 3-clique models: ABC:BCD:CDE
  block:
    echo ""
    echo "3-clique chain models"
    for n in [4, 5, 6]:
      let varList = makeTestVarList(n, 2)  # Binary to avoid huge state space
      let inputTable = generateRandomTable(varList)

      var rels: seq[Relation]
      for i in 0..<(n-2):
        rels.add(initRelation(@[VariableIndex(i), VariableIndex(i+1), VariableIndex(i+2)]))
      let model = initModel(rels)

      let name = fmt"3-Clique-{n}vars (ABC:BCD:...)"
      let r = benchmarkModel(name, varList, model, inputTable)
      results.add(r)
      echo fmt"  {name}: IPF={r.ipfTimeMs:.3f}ms, BP={r.bpTimeMs:.3f}ms, speedup={r.speedup:.2f}x"

  printResults(results)


when isMainModule:
  main()
