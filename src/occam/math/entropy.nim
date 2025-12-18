## Entropy calculations for OCCAM
## Shannon entropy, transmission (KL divergence), and related measures

{.push raises: [].}

import std/[math, options]
import ../core/types
import ../core/variable
import ../core/table

func entropy*(t: ContingencyTable): float64 =
  ## Compute Shannon entropy H(X) = -sum(p * log2(p))
  ## Input table should contain probabilities (normalized)
  result = 0.0
  for tup in t:
    if tup.value > ProbMin:
      result -= tup.value * log2(tup.value)


func transmission*(p, q: ContingencyTable): float64 =
  ## Compute transmission (Kullback-Leibler divergence)
  ## T = KL(P||Q) = sum(p * log2(p/q))
  ## Both tables should be sorted and contain probabilities
  result = 0.0
  for tup in p:
    if tup.value > ProbMin:
      let qIdx = q.find(tup.key)
      if qIdx.isSome:
        let qVal = q[qIdx.get].value
        if qVal > ProbMin:
          result += tup.value * log2(tup.value / qVal)


func maxEntropy*(varList: VariableList): float64 =
  ## Compute maximum entropy for the full state space
  ## H_max = log2(NC) where NC is the Cartesian product of all cardinalities
  var nc: int64 = 1
  for v in varList:
    nc *= v.cardinality.toInt
  if nc > 0:
    log2(float64(nc))
  else:
    0.0


func maxEntropyForRelation*(varList: VariableList; varIndices: openArray[VariableIndex]): float64 =
  ## Compute maximum entropy for a subset of variables
  ## H_max = log2(NC) where NC is the product of included variable cardinalities
  var nc: int64 = 1
  for idx in varIndices:
    nc *= varList[idx].cardinality.toInt
  if nc > 0:
    log2(float64(nc))
  else:
    0.0

