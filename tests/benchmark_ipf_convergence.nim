## IPF Convergence Profiling for OCCAM-Nim
##
## Analyzes what drives IPF iteration counts and convergence behavior.
## Run with: nim c -r -d:release tests/benchmark_ipf_convergence.nim
##
## Output: benchmarks/ipf_convergence_YYYYMMDD_HHMMSS.json

import std/[times, monotimes, json, os, strformat, strutils, math, algorithm]
import ../src/occam/core/timing
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table as coretable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/vb
import ../src/occam/math/ipf

const
  RunsPerTest = 3


type
  IPFProfile* = object
    modelName*: string
    modelSpec*: string
    numVariables*: int
    numRelations*: int
    stateSpace*: int
    hasLoop*: bool
    iterationCount*: int
    converged*: bool
    finalError*: float64
    totalTimeNs*: int64
    avgIterTimeNs*: float64
    errorHistory*: seq[float64]
    iterationTimesNs*: seq[int64]

  ConvergenceExperiment* = object
    name*: string
    description*: string
    profiles*: seq[IPFProfile]


proc makeTestVarList(n: int; cardinality = 3): VariableList =
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


proc stateSpace(numVars, cardinality: int): int =
  var result = 1
  for _ in 0..<numVars:
    result *= cardinality
  result


proc profileIPFRun(varList: VariableList; table: coretable.Table;
                   modelSpec: string; modelName: string): IPFProfile =
  result.modelName = modelName
  result.modelSpec = modelSpec
  result.numVariables = varList.len
  result.stateSpace = table.len

  var mgr = initVBManager(varList, table)
  let model = mgr.makeModel(modelSpec)
  result.numRelations = model.relationCount
  result.hasLoop = model.hasLoops(varList)

  if not result.hasLoop:
    # Loopless - no IPF
    result.iterationCount = 0
    result.converged = true
    result.finalError = 0.0
    let start = getMonoTime()
    discard mgr.computeAIC(model)
    result.totalTimeNs = (getMonoTime() - start).inNanoseconds
    return

  # Run IPF with timing enabled
  let config = initIPFConfig(recordIterationTimes = true)
  let ipfResult = ipf.ipf(table, model.relations, varList, config)

  result.iterationCount = ipfResult.iterations
  result.converged = ipfResult.converged
  result.finalError = ipfResult.error
  result.totalTimeNs = ipfResult.totalTimeNs
  result.errorHistory = ipfResult.errorHistory
  result.iterationTimesNs = ipfResult.iterationTimesNs

  if ipfResult.iterationTimesNs.len > 0:
    var total: int64 = 0
    for t in ipfResult.iterationTimesNs:
      total += t
    result.avgIterTimeNs = float64(total) / float64(ipfResult.iterationTimesNs.len)


proc computeDecayRate(errors: seq[float64]): float64 =
  ## Estimate exponential decay rate from error history
  ## Higher rate = faster convergence
  if errors.len < 2:
    return 0.0

  # Simple linear regression on log(error)
  var sumX, sumY, sumXY, sumX2 = 0.0
  var validCount = 0

  for i, e in errors:
    if e > 0:
      let x = float64(i)
      let y = ln(e)
      sumX += x
      sumY += y
      sumXY += x * y
      sumX2 += x * x
      validCount += 1

  if validCount < 2:
    return 0.0

  let n = float64(validCount)
  let denom = n * sumX2 - sumX * sumX
  if abs(denom) < 1e-10:
    return 0.0

  # Negative slope = decay
  -((n * sumXY - sumX * sumY) / denom)


# ============ Experiments ============

proc experimentByLoopComplexity(): ConvergenceExperiment =
  result.name = "loop_complexity"
  result.description = "How does loop complexity affect convergence?"
  result.profiles = @[]

  echo "  Testing loop complexity..."

  # 3-variable triangle
  block:
    let varList = makeTestVarList(3, 3)
    let table = makeRandomTable(varList)
    echo "    Triangle (3 vars)..."
    result.profiles.add(profileIPFRun(varList, table, "AB:BC:AC", "triangle_3"))

  # 4-variable square
  block:
    let varList = makeTestVarList(4, 3)
    let table = makeRandomTable(varList)
    echo "    Square (4 vars)..."
    result.profiles.add(profileIPFRun(varList, table, "AB:BC:CD:AD", "square_4"))

  # 4-variable K4 (complete graph)
  block:
    let varList = makeTestVarList(4, 3)
    let table = makeRandomTable(varList)
    echo "    K4 complete (4 vars)..."
    result.profiles.add(profileIPFRun(varList, table, "AB:AC:AD:BC:BD:CD", "k4_4"))

  # 5-variable pentagon
  block:
    let varList = makeTestVarList(5, 2)  # Lower card to keep state space manageable
    let table = makeRandomTable(varList)
    echo "    Pentagon (5 vars)..."
    result.profiles.add(profileIPFRun(varList, table, "AB:BC:CD:DE:AE", "pentagon_5"))


proc experimentByCardinality(): ConvergenceExperiment =
  result.name = "cardinality"
  result.description = "How does cardinality affect IPF convergence?"
  result.profiles = @[]

  echo "  Testing cardinality effect on triangle model..."

  for card in 2..5:
    let ss = stateSpace(3, card)
    echo fmt"    Cardinality {card} (state space: {ss})..."

    let varList = makeTestVarList(3, card)
    let table = makeRandomTable(varList)
    result.profiles.add(profileIPFRun(varList, table, "AB:BC:AC", fmt"triangle_card{card}"))


proc experimentByThreshold(): ConvergenceExperiment =
  result.name = "threshold"
  result.description = "How does convergence threshold affect iteration count?"
  result.profiles = @[]

  echo "  Testing convergence threshold..."

  let varList = makeTestVarList(4, 3)
  let table = makeRandomTable(varList)
  var mgr = initVBManager(varList, table)
  let model = mgr.makeModel("AB:BC:AC")  # Triangle

  for logThreshold in @[-5, -6, -7, -8, -9, -10]:
    let threshold = pow(10.0, float64(logThreshold))
    echo fmt"    Threshold 1e{logThreshold}..."

    let config = initIPFConfig(
      convergenceThreshold = threshold,
      recordIterationTimes = true
    )

    let ipfResult = ipf.ipf(table, model.relations, varList, config)

    result.profiles.add(IPFProfile(
      modelName: fmt"thresh_1e{logThreshold}",
      modelSpec: "AB:BC:AC",
      numVariables: 4,
      numRelations: 3,
      stateSpace: table.len,
      hasLoop: true,
      iterationCount: ipfResult.iterations,
      converged: ipfResult.converged,
      finalError: ipfResult.error,
      totalTimeNs: ipfResult.totalTimeNs,
      errorHistory: ipfResult.errorHistory
    ))


proc experimentByVariables(): ConvergenceExperiment =
  result.name = "variables"
  result.description = "How does variable count affect IPF (constant structure)?"
  result.profiles = @[]

  echo "  Testing variable count on chain+loop model..."

  for numVars in 4..7:
    let ss = stateSpace(numVars, 2)
    if ss > 10000:
      break
    echo fmt"    {numVars} variables (state space: {ss})..."

    let varList = makeTestVarList(numVars, 2)
    let table = makeRandomTable(varList)

    # Build chain + closing edge to create one loop
    var parts: seq[string]
    for i in 0..<(numVars - 1):
      parts.add($chr(ord('A') + i) & $chr(ord('A') + i + 1))
    parts.add("A" & $chr(ord('A') + numVars - 1))  # Close the loop
    let spec = parts.join(":")

    result.profiles.add(profileIPFRun(varList, table, spec, fmt"cycle_{numVars}"))


proc toJson(profile: IPFProfile): JsonNode =
  %*{
    "modelName": profile.modelName,
    "modelSpec": profile.modelSpec,
    "numVariables": profile.numVariables,
    "numRelations": profile.numRelations,
    "stateSpace": profile.stateSpace,
    "hasLoop": profile.hasLoop,
    "iterationCount": profile.iterationCount,
    "converged": profile.converged,
    "finalError": profile.finalError,
    "totalTimeNs": profile.totalTimeNs,
    "totalTimeFormatted": formatDuration(profile.totalTimeNs),
    "avgIterTimeNs": profile.avgIterTimeNs,
    "avgIterTimeFormatted": formatDuration(int64(profile.avgIterTimeNs)),
    "decayRate": computeDecayRate(profile.errorHistory),
    "errorHistoryLen": profile.errorHistory.len
  }


proc toJson(exp: ConvergenceExperiment): JsonNode =
  var profiles = newJArray()
  for p in exp.profiles:
    profiles.add(p.toJson())

  %*{
    "name": exp.name,
    "description": exp.description,
    "profiles": profiles
  }


proc printExperimentSummary(exp: ConvergenceExperiment) =
  echo fmt"    {exp.name}:"
  for p in exp.profiles:
    let timeStr = formatDuration(p.totalTimeNs)
    let iterStr = if p.iterationCount > 0: fmt"{p.iterationCount} iters" else: "N/A"
    let convStr = if p.converged: "OK" else: "FAIL"
    echo fmt"      {p.modelName}: {timeStr} ({iterStr}, {convStr})"


proc main() =
  echo ""
  echo "=" .repeat(80)
  echo "IPF CONVERGENCE PROFILING"
  echo "=" .repeat(80)
  echo ""

  var experiments: seq[ConvergenceExperiment]

  echo "1. Loop complexity experiment..."
  experiments.add(experimentByLoopComplexity())

  echo ""
  echo "2. Cardinality experiment..."
  experiments.add(experimentByCardinality())

  echo ""
  echo "3. Convergence threshold experiment..."
  experiments.add(experimentByThreshold())

  echo ""
  echo "4. Variable count experiment..."
  experiments.add(experimentByVariables())

  # Print summary
  echo ""
  echo "=" .repeat(80)
  echo "SUMMARY"
  echo "=" .repeat(80)
  echo ""

  for exp in experiments:
    printExperimentSummary(exp)
    echo ""

  # Key findings
  echo "-" .repeat(80)
  echo "KEY OBSERVATIONS:"
  echo ""

  # Find experiment with highest iteration count
  var maxIter = 0
  var maxIterModel = ""
  for exp in experiments:
    for p in exp.profiles:
      if p.iterationCount > maxIter:
        maxIter = p.iterationCount
        maxIterModel = p.modelName

  if maxIter > 0:
    echo fmt"  - Highest iteration count: {maxIter} ({maxIterModel})"

  # Compare triangle at different cardinalities
  for exp in experiments:
    if exp.name == "cardinality":
      if exp.profiles.len >= 2:
        let first = exp.profiles[0]
        let last = exp.profiles[^1]
        let ratio = float64(last.totalTimeNs) / float64(first.totalTimeNs)
        echo fmt"  - Cardinality scaling: {ratio:.1f}x from card={first.modelSpec} to card={last.modelSpec}"
      break

  echo ""

  # Save results
  createDir("benchmarks")
  let timestamp = now().format("yyyyMMdd'_'HHmmss")
  let filename = fmt"benchmarks/ipf_convergence_{timestamp}.json"

  var expJson = newJArray()
  for exp in experiments:
    expJson.add(exp.toJson())

  let output = %*{
    "timestamp": $now(),
    "experiments": expJson
  }

  writeFile(filename, pretty(output))
  echo fmt"Results saved to: {filename}"
  echo ""


when isMainModule:
  main()
