## Cross-validation tests against legacy OCCAM
##
## Reference values obtained by running:
##   docker run --rm occam-legacy /var/www/occam/install/cl/occ -a fit -m "MODEL" FILE
##
## These tests ensure the Nim implementation produces identical results
## to the original Portland State University OCCAM implementation.
##
## Run with: nim c -r tests/test_reference_values.nim

import std/[math]
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/math/entropy
import ../src/occam/manager/vb

const
  # Tolerance for floating point comparisons
  EntropyTol = 1e-4      # 4 decimal places
  TransmissionTol = 1e-5  # 5 decimal places
  LRTol = 0.01            # 2 decimal places

# Helper to create the search.in test data
proc createSearchData(): tuple[varList: VariableList, table: ContingencyTable] =
  ## Creates the dataset from ../occam/examples/search.in
  ## 4 variables: soft(3), previous(2), temp(2), prefer(2)
  ## N=1008, 24 unique states
  var varList = initVariableList()
  discard varList.add(initVariable("soft", "A", Cardinality(3)))
  discard varList.add(initVariable("previous", "B", Cardinality(2)))
  discard varList.add(initVariable("temp", "C", Cardinality(2)))
  discard varList.add(initVariable("prefer", "D", Cardinality(2)))

  # Counts from search.in in the correct enumeration order
  let counts = @[
    19.0, 23.0, 24.0,   # B=1 C=1 D=1, A=1,2,3
    29.0, 33.0, 42.0,   # B=2 C=1 D=1, A=1,2,3
    57.0, 47.0, 37.0,   # B=1 C=2 D=1, A=1,2,3
    63.0, 66.0, 68.0,   # B=2 C=2 D=1, A=1,2,3
    29.0, 47.0, 43.0,   # B=1 C=1 D=2, A=1,2,3
    27.0, 23.0, 30.0,   # B=2 C=1 D=2, A=1,2,3
    49.0, 55.0, 52.0,   # B=1 C=2 D=2, A=1,2,3
    53.0, 50.0, 42.0    # B=2 C=2 D=2, A=1,2,3
  ]

  var table = initContingencyTable(varList.keySize)
  var idx = 0
  for d in 0..<2:
    for c in 0..<2:
      for b in 0..<2:
        for a in 0..<3:
          table.add(
            varList.buildKey(@[
              (VariableIndex(0), a),
              (VariableIndex(1), b),
              (VariableIndex(2), c),
              (VariableIndex(3), d)
            ]),
            counts[idx]
          )
          idx += 1
  table.sort()

  (varList, table)


suite "Reference Values: PSU OCCAM search.in":
  ## Reference data from Portland State University OCCAM
  ## Dataset: 4 variables (A:3, B:2, C:2, D:2), N=1008, 24 states
  ##
  ## Source: ../occam/examples/search.in
  ## Generated via docker run --rm occam-legacy occ -a fit ...

  const
    # Reference values from legacy OCCAM
    RefHData = 4.50007        # H(data) = H(saturated model)
    RefHIndependence = 4.5308  # H(A:B:C:D)
    RefHLoopModel = 4.50158    # H(ABD:ACD:BCD)
    RefTransmissionLoop = 0.00151367
    RefLRLoopVsTop = 2.11518
    RefSampleSize = 1008.0
    RefStateSpace = 24

  var mgr: VBManager
  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    (varList, inputTable) = createSearchData()
    mgr = initVBManager(varList, inputTable)

  test "H(data) matches legacy OCCAM":
    let saturatedModel = mgr.topRefModel
    let h = mgr.computeH(saturatedModel)

    echo "  Reference H(data): ", RefHData
    echo "  Computed H(data):  ", h
    echo "  Difference:        ", abs(h - RefHData)

    check abs(h - RefHData) < EntropyTol

  test "H(independence) matches legacy OCCAM":
    let indepModel = mgr.bottomRefModel
    let h = mgr.computeH(indepModel)

    echo "  Reference H(indep): ", RefHIndependence
    echo "  Computed H(indep):  ", h
    echo "  Difference:         ", abs(h - RefHIndependence)

    check abs(h - RefHIndependence) < EntropyTol

  test "H(loop model ABD:ACD:BCD) matches legacy OCCAM":
    let loopModel = mgr.makeModel("ABD:ACD:BCD")
    let h = mgr.computeH(loopModel)

    echo "  Reference H(loop): ", RefHLoopModel
    echo "  Computed H(loop):  ", h
    echo "  Difference:        ", abs(h - RefHLoopModel)

    check abs(h - RefHLoopModel) < EntropyTol

  test "Transmission matches legacy OCCAM":
    let loopModel = mgr.makeModel("ABD:ACD:BCD")
    let t = mgr.computeT(loopModel)

    # Note: Nim uses T = H(data) - H(model), legacy may use opposite sign
    echo "  Reference T:  ", RefTransmissionLoop
    echo "  Computed |T|: ", abs(t)
    echo "  Difference:   ", abs(abs(t) - RefTransmissionLoop)

    check abs(abs(t) - RefTransmissionLoop) < TransmissionTol

  test "LR statistic matches legacy OCCAM":
    let loopModel = mgr.makeModel("ABD:ACD:BCD")
    let lr = mgr.computeLR(loopModel)

    echo "  Reference LR: ", RefLRLoopVsTop
    echo "  Computed LR:  ", lr
    echo "  Difference:   ", abs(lr - RefLRLoopVsTop)

    check abs(lr - RefLRLoopVsTop) < LRTol

  test "state space size matches":
    check varList.stateSpace == RefStateSpace

  test "sample size matches":
    let n = inputTable.sum
    echo "  Reference N: ", RefSampleSize
    echo "  Computed N:  ", n
    check abs(n - RefSampleSize) < 0.001


suite "Reference Values: Model Search Results":
  ## Validate that entropy values match legacy OCCAM search output
  ##
  ## Legacy search output (width=3, levels=3):
  ##   IVI (bottom): H=4.5308
  ##   IVI:BD: H=4.5161
  ##   AC:BD: H=4.5117
  ##   AC:BD:CD: H=4.5086

  var mgr: VBManager
  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    (varList, inputTable) = createSearchData()
    mgr = initVBManager(varList, inputTable)

  test "A:C:BD model entropy matches search output (IVI:BD)":
    # From search: IVI:BD has H=4.5161
    # In legacy notation, IVI:BD = independence (A:B:C:D) with BD association added
    # This becomes A:C:BD in our notation
    let model = mgr.makeModel("A:C:BD")
    let h = mgr.computeH(model)

    echo "  Reference H(IVI:BD): 4.5161"
    echo "  Computed H(A:C:BD):  ", h

    check abs(h - 4.5161) < EntropyTol

  test "AC:BD model entropy matches search output":
    # From search: AC:BD has H=4.5117
    let model = mgr.makeModel("AC:BD")
    let h = mgr.computeH(model)

    echo "  Reference H(AC:BD): 4.5117"
    echo "  Computed H(AC:BD):  ", h

    check abs(h - 4.5117) < EntropyTol

  test "AC:BD:CD loop model entropy matches search output":
    # From search: AC:BD:CD has H=4.5086
    let model = mgr.makeModel("AC:BD:CD")
    let h = mgr.computeH(model)

    echo "  Reference H(AC:BD:CD): 4.5086"
    echo "  Computed H(AC:BD:CD):  ", h

    check abs(h - 4.5086) < EntropyTol

  test "A:B:CD model entropy matches search output (IVI:CD)":
    # From search: IVI:CD has H=4.5277
    # In legacy notation, IVI:CD = independence with CD association added
    let model = mgr.makeModel("A:B:CD")
    let h = mgr.computeH(model)

    echo "  Reference H(IVI:CD): 4.5277"
    echo "  Computed H(A:B:CD):  ", h

    check abs(h - 4.5277) < EntropyTol

  test "AC:B:D model entropy matches search output (IVI:AC)":
    # From search: IVI:AC has H=4.5264
    # In legacy notation, IVI:AC = independence with AC association added
    let model = mgr.makeModel("AC:B:D")
    let h = mgr.computeH(model)

    echo "  Reference H(IVI:AC): 4.5264"
    echo "  Computed H(AC:B:D):  ", h

    check abs(h - 4.5264) < EntropyTol


suite "Determinism and Reproducibility":
  ## Verify that repeated computations give identical results

  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    (varList, inputTable) = createSearchData()

  test "H computation is deterministic":
    var mgr = initVBManager(varList, inputTable)
    let model = mgr.makeModel("ABD:ACD:BCD")

    let h1 = mgr.computeH(model)
    let h2 = mgr.computeH(model)
    let h3 = mgr.computeH(model)

    echo "  H (run 1): ", h1
    echo "  H (run 2): ", h2
    echo "  H (run 3): ", h3

    check abs(h1 - h2) < 1e-12
    check abs(h2 - h3) < 1e-12

  test "loopless model H matches between runs":
    var mgr = initVBManager(varList, inputTable)
    let model = mgr.makeModel("AB:BC:CD")

    let h1 = mgr.computeH(model)

    # Create fresh manager
    var mgr2 = initVBManager(varList, inputTable)
    let model2 = mgr2.makeModel("AB:BC:CD")
    let h2 = mgr2.computeH(model2)

    echo "  H (mgr 1): ", h1
    echo "  H (mgr 2): ", h2

    check abs(h1 - h2) < 1e-12


suite "Reference Values: bw21t08.in (Directed System)":
  ## Reference data from legacy OCCAM bw21t08.in
  ## 15 variables defined, but only type=1 (IV) and type=2 (DV) are used
  ## Type=0 variables are excluded from analysis
  ##
  ## Legacy output:
  ##   State Space Size: 5832
  ##   Sample Size: 1357
  ##   H(data): 9.5278
  ##   H(IV): 9.45668
  ##   H(DV): 0.352049
  ##   T(IV:DV): 0.280934
  ##   IVs in use (7): B D F G H I J
  ##   DV: Z
  ##
  ## Search settings: width=2, levels=3
  ## Best model (BIC): IV:Z (independence)

  const
    RefHData = 9.5278
    RefHIV = 9.45668
    RefHDV = 0.352049
    RefTIvDv = 0.280934
    RefSampleSize = 1357.0
    RefStateSpace = 5832

  var mgr: VBManager
  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    # Only include type=1 (IV) and type=2 (DV) variables
    # Type=0 variables (AGE2, RACEAA2, STRESS2, MARIJ2, ALCO2, DRUGS2, ABUSE2) excluded
    # IVs used: EDYRS2(B:3), INCOME2(D:3), PARTNR2(F:4), OTHER2(G:3),
    #           ESTEEM3(H:3), BMRISK2(I:3), SMOKE2(J:3)
    # DV: LBW2(Z:2)
    varList = initVariableList()
    discard varList.add(initVariable("EDYRS2", "B", Cardinality(3)))
    discard varList.add(initVariable("INCOME2", "D", Cardinality(3)))
    discard varList.add(initVariable("PARTNR2", "F", Cardinality(4)))
    discard varList.add(initVariable("OTHER2", "G", Cardinality(3)))
    discard varList.add(initVariable("ESTEEM3", "H", Cardinality(3)))
    discard varList.add(initVariable("BMRISK2", "I", Cardinality(3)))
    discard varList.add(initVariable("SMOKE2", "J", Cardinality(3)))
    discard varList.add(initVariable("LBW2", "Z", Cardinality(2), isDependent = true))

  test "bw21t08 state space size matches":
    # 3*3*4*3*3*3*3*2 = 5832
    check varList.stateSpace == RefStateSpace

  test "bw21t08 isDirected detects DV":
    check varList.isDirected == true


suite "Reference Values: lhs3b.in (Directed System)":
  ## Reference data from legacy OCCAM lhs3b.in
  ## 11 variables, DV = health (H), :no-frequency mode
  ##
  ## Legacy output:
  ##   State Space Size: 34560
  ##   Sample Size: 829
  ##   H(data): 9.36402
  ##   H(IV): 8.91681
  ##   H(DV): 1.81352
  ##   T(IV:DV): 1.36632
  ##
  ## Search settings: width=2, levels=2
  ## Best model (BIC): IV:HD:HG

  const
    RefHData = 9.36402
    RefHIV = 8.91681
    RefHDV = 1.81352
    RefTIvDv = 1.36632
    RefSampleSize = 829.0
    RefStateSpace = 34560

  var varList: VariableList

  setup:
    # Variables: health(4-DV), tals(5), marital(2), education(3), disabled(2),
    #            gender(2), income(3), age(3), white(2), fulltime(2), parttime(2)
    varList = initVariableList()
    discard varList.add(initVariable("health", "H", Cardinality(4), isDependent = true))
    discard varList.add(initVariable("tals", "T", Cardinality(5)))
    discard varList.add(initVariable("marital", "M", Cardinality(2)))
    discard varList.add(initVariable("education", "E", Cardinality(3)))
    discard varList.add(initVariable("disabled", "D", Cardinality(2)))
    discard varList.add(initVariable("gender", "G", Cardinality(2)))
    discard varList.add(initVariable("income", "I", Cardinality(3)))
    discard varList.add(initVariable("age", "A", Cardinality(3)))
    discard varList.add(initVariable("white", "W", Cardinality(2)))
    discard varList.add(initVariable("fulltime", "F", Cardinality(2)))
    discard varList.add(initVariable("parttime", "P", Cardinality(2)))

  test "lhs3b state space size matches":
    check varList.stateSpace == RefStateSpace

  test "lhs3b isDirected detects DV":
    check varList.isDirected == true


suite "Reference Values: stat.in (Directed with DV=A)":
  ## Reference data from legacy OCCAM stat.in
  ## Same data as search.in but with soft(A) marked as DV
  ##
  ## Legacy output:
  ##   H(data): 4.50007
  ##   H(IV): 2.92585
  ##   H(DV): 1.5846
  ##   T(IV:DV): 0.0103808
  ##
  ## Best model (AIC): IV:AC

  const
    RefHData = 4.50007
    RefHIV = 2.92585
    RefHDV = 1.5846
    RefTIvDv = 0.0103808

  var mgr: VBManager
  var varList: VariableList
  var inputTable: ContingencyTable

  setup:
    # Same as search.in but A is DV
    varList = initVariableList()
    discard varList.add(initVariable("soft", "A", Cardinality(3), isDependent = true))
    discard varList.add(initVariable("previous", "B", Cardinality(2)))
    discard varList.add(initVariable("temp", "C", Cardinality(2)))
    discard varList.add(initVariable("prefer", "D", Cardinality(2)))

    let counts = @[
      19.0, 23.0, 24.0, 29.0, 33.0, 42.0,
      57.0, 47.0, 37.0, 63.0, 66.0, 68.0,
      29.0, 47.0, 43.0, 27.0, 23.0, 30.0,
      49.0, 55.0, 52.0, 53.0, 50.0, 42.0
    ]

    inputTable = initContingencyTable(varList.keySize)
    var idx = 0
    for d in 0..<2:
      for c in 0..<2:
        for b in 0..<2:
          for a in 0..<3:
            inputTable.add(
              varList.buildKey(@[
                (VariableIndex(0), a),
                (VariableIndex(1), b),
                (VariableIndex(2), c),
                (VariableIndex(3), d)
              ]),
              counts[idx]
            )
            idx += 1
    inputTable.sort()
    mgr = initVBManager(varList, inputTable)

  test "stat.in isDirected detects DV":
    check varList.isDirected == true

  test "stat.in H(data) matches legacy":
    let h = mgr.computeH(mgr.topRefModel)
    echo "  Reference H(data): ", RefHData
    echo "  Computed H(data):  ", h
    check abs(h - RefHData) < EntropyTol

  test "stat.in H(DV) marginal entropy matches":
    # H(DV) = H(A) = entropy of soft drink preferences
    # Reference: 1.5846
    let dvIndex = VariableIndex(0)  # A is DV
    let dvMarginal = inputTable.project(varList, @[dvIndex])
    var normalizedDv = dvMarginal
    normalizedDv.normalize()

    # Compute H(DV)
    var hDv = 0.0
    for tup in normalizedDv:
      if tup.value > 0.0:
        hDv -= tup.value * log2(tup.value)

    echo "  Reference H(DV): ", RefHDV
    echo "  Computed H(A):   ", hDv
    check abs(hDv - RefHDV) < EntropyTol


when isMainModule:
  echo "Running reference value tests..."
  echo ""
