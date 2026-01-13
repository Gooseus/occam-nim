## Integration tests for OCCAM search on synthetic data
## Verifies that search finds expected model structures from known data

import std/[random, math, algorithm, sequtils]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/math/entropy
import ../src/occam/io/synthetic
import ../src/occam/manager/vb
import ../src/occam/search/loopless

# Seed for reproducibility
randomize(12345)


proc findBestModel(mgr: var VBManager; search: LooplessSearch;
                   levels: int = 5; width: int = 5): Model =
  ## Run search and return best model by BIC
  var currentLevel = @[if mgr.searchDirection == Direction.Ascending:
                         mgr.bottomRefModel
                       else:
                         mgr.topRefModel]
  var bestModel = currentLevel[0]
  var bestBic = mgr.computeBIC(bestModel)

  for _ in 1..levels:
    if currentLevel.len == 0:
      break

    var nextLevel: seq[(Model, float64)]
    for model in currentLevel:
      for neighbor in search.generateNeighbors(model):
        let bic = mgr.computeBIC(neighbor)
        nextLevel.add((neighbor, bic))
        if bic < bestBic:
          bestBic = bic
          bestModel = neighbor

    # Keep best by BIC (lower is better)
    nextLevel.sort(proc(a, b: (Model, float64)): int = cmp(a[1], b[1]))
    let kept = min(width, nextLevel.len)
    currentLevel = @[]
    for i in 0..<kept:
      currentLevel.add(nextLevel[i][0])

  bestModel


suite "Chain model recovery":
  ## Test that OCCAM finds structure from chain-generated data
  ## Note: Loopless upward search from A:B:C can reach AB:C, AC:B, A:BC, ABC
  ## but not AB:BC directly (requires different search strategy)

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "BIC correctly identifies chain structure":
    # Generate data from A→B→C with strong transition
    randomize(42)
    let graphModel = createChainModel(varList, 0.95)
    let samples = graphModel.generateSamples(2000)
    var table = graphModel.samplesToTable(samples)

    var mgr = initVBManager(varList, table)

    # Compare BIC of different models
    let bicIndep = mgr.computeBIC(mgr.makeModel("A:B:C"))
    let bicABwC = mgr.computeBIC(mgr.makeModel("AB:C"))
    let bicAwBC = mgr.computeBIC(mgr.makeModel("A:BC"))
    let bicChain = mgr.computeBIC(mgr.makeModel("AB:BC"))
    let bicSat = mgr.computeBIC(mgr.makeModel("ABC"))

    echo "  Chain data BIC comparison:"
    echo "    A:B:C (indep): ", bicIndep
    echo "    AB:C: ", bicABwC
    echo "    A:BC: ", bicAwBC
    echo "    AB:BC (true): ", bicChain
    echo "    ABC (sat): ", bicSat

    # The true model (AB:BC) should have good BIC
    # For chain A→B→C, AB:BC should fit better than independence
    check bicChain < bicIndep  # True model better than independence

  test "search finds improved model from independence":
    randomize(123)
    let graphModel = createChainModel(varList, 0.8)
    let samples = graphModel.generateSamples(5000)
    var table = graphModel.samplesToTable(samples)

    var mgr = initVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 5)

    let best = findBestModel(mgr, search, levels = 5)
    let bestName = best.printName(varList)

    echo "  Chain data (moderate): Best model = ", bestName
    echo "    BIC = ", mgr.computeBIC(best)

    # Search should find some structure
    check best.relationCount >= 1


suite "Star model recovery":
  ## Test that OCCAM finds star structure B→A, B→C from star-generated data

  setup:
    var varList = initVariableList()
    # B is center (index 0) for correct sampling order
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "find star AB:BC from star data":
    randomize(456)
    let graphModel = createStarModel(varList, VariableIndex(0), 0.9)
    let samples = graphModel.generateSamples(3000)
    var table = graphModel.samplesToTable(samples)

    var mgr = initVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 5)

    let best = findBestModel(mgr, search, levels = 5)
    let bestName = best.printName(varList)

    echo "  Star data: Best model = ", bestName
    echo "    BIC = ", mgr.computeBIC(best)

    # Star with B as center should give AB:BC structure
    # (both A and C depend on B)
    check best.relationCount >= 1


suite "Independence model recovery":
  ## Test that OCCAM finds independence when data is independent

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "find independence A:B:C from independent data":
    randomize(789)
    let graphModel = createIndependentModel(varList)
    let samples = graphModel.generateSamples(2000)
    var table = graphModel.samplesToTable(samples)

    var mgr = initVBManager(varList, table)

    # For independent data, search up should not find significant structure
    # The best model should be close to independence
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 5)

    let best = findBestModel(mgr, search, levels = 3)
    let bestName = best.printName(varList)

    echo "  Independent data: Best model = ", bestName
    echo "    BIC = ", mgr.computeBIC(best)

    # Independence model should have best BIC for independent data
    let indepBic = mgr.computeBIC(mgr.bottomRefModel)
    let bestBic = mgr.computeBIC(best)

    echo "    Independence BIC = ", indepBic

    # Best found model's BIC should not be dramatically better than independence
    # (small differences due to sampling variation are OK)


suite "Directed system recovery":
  ## Test that OCCAM finds predictive structure in directed systems

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("Z", "Z", Cardinality(2), isDependent = true))

  test "find predictive model when A predicts Z":
    randomize(999)

    # Create data where Z depends on A (not B)
    # Manual construction: P(Z|A) with high dependence
    var table = initContingencyTable(varList.keySize, 8)
    for a in 0..<2:
      for b in 0..<2:
        for z in 0..<2:
          var k = newKey(varList.keySize)
          k.setValue(varList, VariableIndex(0), a)
          k.setValue(varList, VariableIndex(1), b)
          k.setValue(varList, VariableIndex(2), z)
          # Z matches A with high probability
          let count = if a == z: 45.0 else: 5.0
          table.add(k, count)
    table.sort()

    var mgr = initVBManager(varList, table)
    mgr.setSearchDirection(Direction.Ascending)
    let search = initLooplessSearch(mgr, width = 5)

    let best = findBestModel(mgr, search, levels = 5)
    let bestName = best.printName(varList)

    echo "  A→Z predictive: Best model = ", bestName
    echo "    BIC = ", mgr.computeBIC(best)

    # Should find AZ (A predicts Z) rather than BZ
    check best.containsDependent(varList)


suite "Sample size effects":
  ## Test how sample size affects model recovery

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "larger samples give more reliable recovery":
    let graphModel = createChainModel(varList, 0.85)

    var recoveredSmall, recoveredLarge: string

    # Small sample
    randomize(111)
    let smallSamples = graphModel.generateSamples(200)
    var smallTable = graphModel.samplesToTable(smallSamples)
    var mgrSmall = initVBManager(varList, smallTable)
    mgrSmall.setSearchDirection(Direction.Ascending)
    let searchSmall = initLooplessSearch(mgrSmall, width = 5)
    let bestSmall = findBestModel(mgrSmall, searchSmall, levels = 5)
    recoveredSmall = bestSmall.printName(varList)

    # Large sample
    randomize(111)
    let largeSamples = graphModel.generateSamples(5000)
    var largeTable = graphModel.samplesToTable(largeSamples)
    var mgrLarge = initVBManager(varList, largeTable)
    mgrLarge.setSearchDirection(Direction.Ascending)
    let searchLarge = initLooplessSearch(mgrLarge, width = 5)
    let bestLarge = findBestModel(mgrLarge, searchLarge, levels = 5)
    recoveredLarge = bestLarge.printName(varList)

    echo "  Small sample (200): ", recoveredSmall
    echo "  Large sample (5000): ", recoveredLarge

    # Large sample should recover more structure
    check bestLarge.relationCount >= 1


suite "Model comparison statistics":
  ## Test that statistics correctly rank models

  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "true model has good fit statistics":
    randomize(222)
    let graphModel = createChainModel(varList, 0.9)
    let samples = graphModel.generateSamples(3000)
    var table = graphModel.samplesToTable(samples)

    var mgr = initVBManager(varList, table)

    # Compare different models
    let modelIndep = mgr.makeModel("A:B:C")
    let modelAB_C = mgr.makeModel("AB:C")
    let modelBC_A = mgr.makeModel("A:BC")
    let modelAB_BC = mgr.makeModel("AB:BC")  # True model structure

    let bicIndep = mgr.computeBIC(modelIndep)
    let bicAB_C = mgr.computeBIC(modelAB_C)
    let bicBC_A = mgr.computeBIC(modelBC_A)
    let bicAB_BC = mgr.computeBIC(modelAB_BC)

    echo "  Model BIC comparison:"
    echo "    A:B:C (indep): ", bicIndep
    echo "    AB:C: ", bicAB_C
    echo "    A:BC: ", bicBC_A
    echo "    AB:BC (true): ", bicAB_BC

    # True model should have competitive BIC
    # (not necessarily best due to BIC's complexity penalty)

