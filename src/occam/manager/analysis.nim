## Analysis procedures for OCCAM
## Computes conditional DV tables and confusion matrices for directed systems

{.push raises: [].}

import std/[tables, sequtils, options]
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/model
import ../core/results
import ../core/errors
import vb

proc computeConditionalDV*(mgr: var VBManager; model: Model): ConditionalDVTable {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute conditional DV table showing P(DV|IVs) for each IV state
  ## Requires a directed system (varList.isDirected == true)

  # Identify IV and DV variables
  var ivIndices: seq[VariableIndex]
  var dvIndex: VariableIndex
  var dvCard = 0

  for vi, v in mgr.varList.pairs:
    if v.isDependent:
      dvIndex = vi
      dvCard = v.cardinality.toInt
    else:
      ivIndices.add(vi)

  result.ivIndices = ivIndices

  # Enumerate all IV state combinations
  let ivCount = ivIndices.len
  var ivCards: seq[int]
  for vi in ivIndices:
    ivCards.add(mgr.varList[vi].cardinality.toInt)

  var totalIVStates = 1
  for c in ivCards:
    totalIVStates *= c

  # Get fitted table for this model
  let fitTable = mgr.makeFitTable(model)

  # For each IV state combination
  var ivStateIndices = newSeq[int](ivCount)
  var done = false

  while not done:
    # Build current IV state
    var ivState: seq[int]
    for i in 0..<ivCount:
      ivState.add(ivStateIndices[i])
    result.ivStates.add(ivState)

    # Compute P(DV=k | IV state) for each DV value
    var dvProbs: seq[float64] = newSeq[float64](dvCard)
    var dvCounts: seq[float64] = newSeq[float64](dvCard)
    var totalProb = 0.0

    for k in 0..<dvCard:
      # Build full key for (IV state, DV=k)
      var keyPairs: seq[(VariableIndex, int)]
      for i, vi in ivIndices:
        keyPairs.add((vi, ivStateIndices[i]))
      keyPairs.add((dvIndex, k))

      let key = mgr.varList.buildKey(keyPairs)
      let idx = fitTable.find(key)
      var prob = 0.0
      if idx.isSome:
        prob = fitTable[idx.get].value

      dvProbs[k] = prob
      totalProb += prob

      # Also get raw counts from input data
      let dataIdx = mgr.inputData.find(key)
      if dataIdx.isSome:
        dvCounts[k] = mgr.inputData[dataIdx.get].value

    # Normalize probabilities
    if totalProb > 0:
      for k in 0..<dvCard:
        dvProbs[k] /= totalProb

    result.dvProbs.add(dvProbs)

    # Prediction: DV value with highest probability
    var maxProb = -1.0
    var prediction = 0
    for k in 0..<dvCard:
      if dvProbs[k] > maxProb:
        maxProb = dvProbs[k]
        prediction = k
    result.predictions.add(prediction)

    # Count correct predictions from raw data
    let correctCount = dvCounts[prediction].int
    let totalCount = dvCounts.foldl(a + b, 0.0).int
    result.correctCounts.add(correctCount)
    result.totalCounts.add(totalCount)

    # Increment IV state indices (last index increments first for lexicographic order)
    var carry = true
    for i in countdown(ivCount - 1, 0):
      if carry:
        ivStateIndices[i] += 1
        if ivStateIndices[i] >= ivCards[i]:
          ivStateIndices[i] = 0
        else:
          carry = false
    if carry:
      done = true

  # Calculate overall percent correct
  var totalCorrect = 0
  var grandTotal = 0
  for i in 0..<result.correctCounts.len:
    totalCorrect += result.correctCounts[i]
    grandTotal += result.totalCounts[i]

  if grandTotal > 0:
    result.percentCorrect = totalCorrect.float64 / grandTotal.float64
  else:
    result.percentCorrect = 0.0


proc computeConfusionMatrix*(mgr: var VBManager; model: Model): ConfusionMatrix {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute confusion matrix comparing actual vs predicted DV values
  ## Rows = actual DV, Columns = predicted DV

  # First get conditional DV table for predictions
  let dvTable = mgr.computeConditionalDV(model)

  # Identify DV variable
  var dvIndex: VariableIndex
  var dvCard = 0

  for vi, v in mgr.varList.pairs:
    if v.isDependent:
      dvIndex = vi
      dvCard = v.cardinality.toInt
      break

  # Initialize confusion matrix
  result.matrix = newSeq[seq[int]](dvCard)
  for i in 0..<dvCard:
    result.matrix[i] = newSeq[int](dvCard)

  # Set labels from DV variable
  let valueMap = mgr.varList[dvIndex].valueMap
  if valueMap.len > 0 and valueMap[0].len > 0:
    result.labels = valueMap
  else:
    # Generate default labels if none exist
    for i in 0..<dvCard:
      result.labels.add($i)

  # Build map from IV state to prediction
  var predictionMap: tables.Table[seq[int], int]
  for i, ivState in dvTable.ivStates:
    predictionMap[ivState] = dvTable.predictions[i]

  # For each cell in input data, add to confusion matrix
  for tup in mgr.inputData:
    # Extract IV state and actual DV from key
    var ivState: seq[int]
    var actualDV = 0

    for i in 0..<mgr.varList.len:
      let vi = VariableIndex(i)
      let v = tup.key.getValue(mgr.varList, vi)
      if mgr.varList[vi].isDependent:
        actualDV = v
      else:
        ivState.add(v)

    # Get prediction for this IV state
    let prediction = predictionMap.getOrDefault(ivState, 0)

    # Add count to confusion matrix
    let count = tup.value.int
    result.matrix[actualDV][prediction] += count

  # Calculate metrics
  var totalCorrect = 0
  var grandTotal = 0

  for i in 0..<dvCard:
    for j in 0..<dvCard:
      grandTotal += result.matrix[i][j]
      if i == j:
        totalCorrect += result.matrix[i][j]

  if grandTotal > 0:
    result.accuracy = totalCorrect.float64 / grandTotal.float64
  else:
    result.accuracy = 0.0

  # Per-class precision and recall
  result.perClassPrecision = newSeq[float64](dvCard)
  result.perClassRecall = newSeq[float64](dvCard)

  for k in 0..<dvCard:
    # Precision = TP / (TP + FP) = matrix[k][k] / sum(col k)
    var colSum = 0
    for i in 0..<dvCard:
      colSum += result.matrix[i][k]

    if colSum > 0:
      result.perClassPrecision[k] = result.matrix[k][k].float64 / colSum.float64
    else:
      result.perClassPrecision[k] = 0.0

    # Recall = TP / (TP + FN) = matrix[k][k] / sum(row k)
    var rowSum = 0
    for j in 0..<dvCard:
      rowSum += result.matrix[k][j]

    if rowSum > 0:
      result.perClassRecall[k] = result.matrix[k][k].float64 / rowSum.float64
    else:
      result.perClassRecall[k] = 0.0

