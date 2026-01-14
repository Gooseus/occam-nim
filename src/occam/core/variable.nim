## Variable and VariableList types for OCCAM
## Handles variable definitions with bit-packing for efficient key encoding

{.push raises: [].}

import std/[tables, strutils, options]
import types

type
  Variable* = object
    ## Single variable definition
    name*: string              ## Full name (max 32 chars)
    abbrev*: string            ## Abbreviated name (max 8 chars)
    cardinality*: Cardinality  ## Number of possible values
    isDependent*: bool         ## Is this a dependent (output) variable?
    segment*: SegmentIndex     ## Which KeySegment contains this variable
    shift*: BitShift           ## Bit position within segment
    bitSize*: int              ## Number of bits needed
    mask*: KeySegment          ## Bitmask for this variable's position
    valueMap*: seq[string]     ## Maps indices to string values

  VariableList* = object
    ## Ordered collection of variables
    variables: seq[Variable]
    abbrevIndex: Table[string, VariableIndex]  ## Fast lookup by abbreviation
    keySegments: int           ## Number of KeySegments needed


func computeBitSize(cardinality: Cardinality): int =
  ## Compute number of bits needed to encode all values PLUS DontCare
  ## We need ceil(log2(cardinality + 1)) bits so that all-1s is reserved for DontCare
  ## and doesn't conflict with the maximum valid value
  if cardinality.toInt <= 1:
    return 1
  # Need to represent values 0..(cardinality-1) AND reserve all-1s for DontCare
  # So we compute bits for cardinality (not cardinality-1)
  var val = cardinality.toInt  # This ensures all-1s is never a valid value
  result = 0
  while val > 0:
    inc result
    val = val shr 1


func initVariable*(name, abbrev: string; cardinality: Cardinality;
                   isDependent = false): Variable =
  ## Create a new variable (segment/shift/mask set when added to list)
  result.name = name
  result.abbrev = if abbrev.len > 0: abbrev[0..0].toUpperAscii & abbrev[1..^1].toLowerAscii
                  else: abbrev
  result.cardinality = cardinality
  result.isDependent = isDependent
  result.valueMap = newSeq[string](cardinality.toInt)
  result.bitSize = computeBitSize(cardinality)
  result.segment = SegmentIndex(0)
  result.shift = BitShift(0)
  result.mask = KeySegment(0)

func initVariableList*(capacity = 16): VariableList =
  ## Initialize an empty variable list
  result.variables = newSeqOfCap[Variable](capacity)
  result.abbrevIndex = initTable[string, VariableIndex]()
  result.keySegments = 0


func len*(list: VariableList): int {.inline.} =
  ## Number of variables in the list
  list.variables.len


func add*(list: var VariableList; v: Variable): VariableIndex =
  ## Add a variable to the list, computing segment/shift/mask
  var newVar = v
  let idx = VariableIndex(list.variables.len)

  if list.variables.len == 0:
    # First variable starts at top of first segment
    newVar.segment = SegmentIndex(0)
    newVar.shift = BitShift(KeySegmentBits - newVar.bitSize)
    list.keySegments = 1
  else:
    let last = list.variables[^1]
    let remainingBits = last.shift.toInt

    if remainingBits >= newVar.bitSize:
      # Fits in current segment
      newVar.segment = last.segment
      newVar.shift = BitShift(remainingBits - newVar.bitSize)
    else:
      # Need new segment
      newVar.segment = SegmentIndex(last.segment.toInt + 1)
      newVar.shift = BitShift(KeySegmentBits - newVar.bitSize)
      list.keySegments = newVar.segment.toInt + 1

  # Build mask with 1s in variable positions
  let ones = (KeySegment(1) shl newVar.bitSize) - KeySegment(1)
  newVar.mask = ones shl newVar.shift.toInt

  list.variables.add(newVar)
  list.abbrevIndex[newVar.abbrev.toLowerAscii] = idx

  result = idx


func `[]`*(list: VariableList; idx: VariableIndex): Variable {.inline.} =
  ## Access variable by index
  list.variables[idx.toInt]


func `[]`*(list: var VariableList; idx: VariableIndex): var Variable {.inline.} =
  ## Access mutable variable by index
  list.variables[idx.toInt]


func findByAbbrev*(list: VariableList; abbrev: string): Option[VariableIndex] =
  ## Find variable index by abbreviation (case insensitive)
  let key = abbrev.toLowerAscii
  try:
    if key in list.abbrevIndex:
      some(list.abbrevIndex[key])
    else:
      none(VariableIndex)
  except KeyError:
    none(VariableIndex)


func keySize*(list: VariableList): int {.inline.} =
  ## Number of KeySegments needed to encode all variables
  list.keySegments


func isDirected*(list: VariableList): bool =
  ## Check if any variable is marked as dependent
  for v in list.variables:
    if v.isDependent:
      return true
  false


func stateSpace*(list: VariableList): int64 =
  ## Compute total state space size (product of all cardinalities)
  if list.len == 0:
    return 0
  result = 1
  for v in list.variables:
    result *= v.cardinality.toInt


func dependentIndex*(list: VariableList): Option[VariableIndex] =
  ## Get the index of the dependent variable if directed
  for i, v in list.variables:
    if v.isDependent:
      return some(VariableIndex(i))
  none(VariableIndex)


iterator items*(list: VariableList): Variable =
  ## Iterate over all variables
  for v in list.variables:
    yield v


iterator pairs*(list: VariableList): (VariableIndex, Variable) =
  ## Iterate with indices
  for i, v in list.variables:
    yield (VariableIndex(i), v)


iterator indices*(list: VariableList): VariableIndex =
  ## Iterate over variable indices only
  for i in 0..<list.variables.len:
    yield VariableIndex(i)
