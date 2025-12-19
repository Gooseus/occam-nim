## Table type for OCCAM
## Sparse contingency tables with key-value tuples
##
## Note: This module exports `Table` which may conflict with `std/tables.Table`.
## For clarity, prefer importing with an alias:
##   import ../core/table as coretable
## Or use the `ContingencyTable` alias for the type name.

{.push raises: [].}

import std/[algorithm, options]
import types
import variable
import key

# Compile-time flag for projection profiling
when defined(profileProjections):
  import std/[monotimes, times]
  import profile

type
  Tuple* = object
    ## A single entry in a contingency table
    key*: Key
    value*: float64

  ContingencyTable* = object
    ## Sparse contingency table
    ## Stores tuples (key-value pairs) sorted by key for efficient lookup
    tuples: seq[Tuple]
    keySegments: int
    sorted: bool

  # Deprecated alias - use ContingencyTable instead
  Table* {.deprecated: "Use ContingencyTable instead".} = ContingencyTable


func initContingencyTable*(keySize: int; capacity = 64): ContingencyTable =
  ## Initialize an empty contingency table with given key size
  result.tuples = newSeqOfCap[Tuple](capacity)
  result.keySegments = keySize
  result.sorted = true  # Empty table is trivially sorted

# Deprecated alias
func initTable*(keySize: int; capacity = 64): ContingencyTable {.deprecated: "Use initContingencyTable instead".} =
  initContingencyTable(keySize, capacity)


func len*(t: ContingencyTable): int {.inline.} =
  ## Number of tuples in the table
  t.tuples.len


func keySize*(t: ContingencyTable): int {.inline.} =
  ## Number of segments in keys
  t.keySegments


func `[]`*(t: ContingencyTable; idx: int): Tuple {.inline.} =
  ## Access tuple by index
  t.tuples[idx]


func `[]`*(t: var ContingencyTable; idx: int): var Tuple {.inline.} =
  ## Access mutable tuple by index
  t.tuples[idx]


func add*(t: var ContingencyTable; key: Key; value: float64) =
  ## Add a tuple to the table
  t.tuples.add(Tuple(key: key, value: value))
  t.sorted = false


func add*(t: var ContingencyTable; tup: Tuple) =
  ## Add a tuple to the table
  t.tuples.add(tup)
  t.sorted = false


func cmpTuples(a, b: Tuple): int =
  ## Compare tuples by key
  cmp(a.key, b.key)


proc sort*(t: var ContingencyTable) =
  ## Sort tuples by key for binary search
  if not t.sorted:
    t.tuples.sort(cmpTuples)
    t.sorted = true


func find*(t: ContingencyTable; key: Key): Option[int] =
  ## Find tuple index by key using binary search
  ## Table must be sorted first
  if t.tuples.len == 0:
    return none(int)

  # Binary search
  var lo = 0
  var hi = t.tuples.len - 1

  while lo <= hi:
    let mid = (lo + hi) div 2
    let c = cmp(t.tuples[mid].key, key)
    if c == 0:
      return some(mid)
    elif c < 0:
      lo = mid + 1
    else:
      hi = mid - 1

  none(int)


func sum*(t: ContingencyTable): float64 =
  ## Sum all values in the table
  result = 0.0
  for tup in t.tuples:
    result += tup.value


proc normalize*(t: var ContingencyTable) =
  ## Normalize values to sum to 1.0 (convert counts to probabilities)
  let total = t.sum
  if total > 0.0:
    for i in 0..<t.tuples.len:
      t.tuples[i].value = t.tuples[i].value / total


proc sumInto*(t: var ContingencyTable) =
  ## Combine tuples with matching keys by summing their values
  ## Table must be sorted first
  if t.tuples.len <= 1:
    return

  t.sort()

  var writeIdx = 0
  var readIdx = 1

  while readIdx < t.tuples.len:
    if t.tuples[writeIdx].key == t.tuples[readIdx].key:
      # Same key - add values
      t.tuples[writeIdx].value += t.tuples[readIdx].value
    else:
      # Different key - move to next write position
      inc writeIdx
      if writeIdx != readIdx:
        t.tuples[writeIdx] = t.tuples[readIdx]
    inc readIdx

  # Truncate to remove duplicates
  t.tuples.setLen(writeIdx + 1)


func projectImpl(t: ContingencyTable; varList: VariableList; varIndices: openArray[VariableIndex]): ContingencyTable =
  ## Internal projection implementation
  # Build mask for projection
  let mask = varList.buildMask(varIndices)

  # Use a temporary table to accumulate
  var projected = initContingencyTable(t.keySegments, t.tuples.len)

  # Project each tuple's key and accumulate
  for tup in t.tuples:
    let projKey = tup.key.applyMask(mask)
    projected.add(projKey, tup.value)

  # Combine duplicates
  projected.sumInto()

  projected


when defined(profileProjections):
  proc project*(t: ContingencyTable; varList: VariableList; varIndices: openArray[VariableIndex]): ContingencyTable =
    ## Project table onto subset of variables (marginalize out others)
    ## Returns new table with combined values for matching projected keys
    ## With -d:profileProjections: tracks call count and timing
    let startTime = getMonoTime()
    result = projectImpl(t, varList, varIndices)
    addProjectionStat(inNanoseconds(getMonoTime() - startTime))

else:
  func project*(t: ContingencyTable; varList: VariableList; varIndices: openArray[VariableIndex]): ContingencyTable =
    ## Project table onto subset of variables (marginalize out others)
    ## Returns new table with combined values for matching projected keys
    projectImpl(t, varList, varIndices)


iterator items*(t: ContingencyTable): Tuple =
  ## Iterate over all tuples
  for tup in t.tuples:
    yield tup


iterator pairs*(t: ContingencyTable): (int, Tuple) =
  ## Iterate with indices
  for i, tup in t.tuples:
    yield (i, tup)

