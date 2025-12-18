## Key type for OCCAM
## Packed representation of variable values using bit encoding

{.push raises: [].}

import std/hashes
import types
import variable

type
  Key* = object
    ## Packed representation of variable values
    ## Each segment is a 32-bit unsigned integer
    segments*: seq[KeySegment]


func initKey*(size: int): Key =
  ## Create a key with given number of segments, initialized to DontCare
  result.segments = newSeq[KeySegment](size)
  for i in 0..<size:
    result.segments[i] = DontCare

# Deprecated alias
func newKey*(size: int): Key {.deprecated: "Use initKey instead".} =
  initKey(size)


func len*(k: Key): int {.inline.} =
  ## Number of segments in the key
  k.segments.len


func `[]`*(k: Key; idx: int): KeySegment {.inline.} =
  ## Access segment by index
  k.segments[idx]


func `[]=`*(k: var Key; idx: int; val: KeySegment) {.inline.} =
  ## Set segment by index
  k.segments[idx] = val


func getValue*(k: Key; varList: VariableList; varIdx: VariableIndex): int {.inline.} =
  ## Extract a single variable's value from a key
  let v = varList[varIdx]
  let segment = v.segment.toInt
  # Extract bits: shift right to align, then mask off high bits
  int((k.segments[segment] and v.mask) shr v.shift.toInt)


func setValue*(k: var Key; varList: VariableList; varIdx: VariableIndex; value: int) {.inline.} =
  ## Set a single variable's value in a key
  let v = varList[varIdx]
  let segment = v.segment.toInt
  # Clear the variable's bits, then set new value
  k.segments[segment] = (k.segments[segment] and (not v.mask)) or
                         ((KeySegment(value) shl v.shift.toInt) and v.mask)


func buildKey*(varList: VariableList; pairs: openArray[(VariableIndex, int)]): Key =
  ## Build a key from variable-value pairs
  ## Unspecified variables are set to DontCare
  result = initKey(varList.keySize)
  for (varIdx, value) in pairs:
    result.setValue(varList, varIdx, value)


func `==`*(a, b: Key): bool =
  ## Check if two keys are exactly equal
  if a.segments.len != b.segments.len:
    return false
  for i in 0..<a.segments.len:
    if a.segments[i] != b.segments[i]:
      return false
  true


func cmp*(a, b: Key): int =
  ## Compare two keys lexicographically
  for i in 0..<min(a.segments.len, b.segments.len):
    if a.segments[i] < b.segments[i]:
      return -1
    if a.segments[i] > b.segments[i]:
      return 1
  cmp(a.segments.len, b.segments.len)


func `<`*(a, b: Key): bool =
  ## Less than comparison for keys
  cmp(a, b) < 0


func hash*(k: Key): Hash =
  ## Hash function for use in tables
  var h: Hash = 0
  for seg in k.segments:
    h = h !& hash(seg.toUint32)
  !$h


func buildMask*(varList: VariableList; varIndices: openArray[VariableIndex]): Key =
  ## Create mask with 0s for included variables, 1s (DontCare) elsewhere
  ## Used for projection operations
  result = initKey(varList.keySize)  # Starts as all 1s (DontCare)
  for varIdx in varIndices:
    let v = varList[varIdx]
    let segment = v.segment.toInt
    # Clear the bits for this variable (set to 0)
    result.segments[segment] = result.segments[segment] and (not v.mask)


func applyMask*(k: Key; mask: Key): Key {.inline.} =
  ## Apply mask to key: where mask is 0, keep key value; where mask is 1, set DontCare
  ## This effectively projects the key onto the variables in the mask
  result = initKey(k.segments.len)
  for i in 0..<k.segments.len:
    # Keep bits where mask is 0, set to 1 (DontCare) where mask is 1
    result.segments[i] = k.segments[i] or mask.segments[i]


func matchesWithVarList*(a, b: Key; varList: VariableList): bool =
  ## Check if two keys match, treating DontCare as wildcard
  ## This version requires the variable list to check per-variable
  if a.segments.len != b.segments.len:
    return false

  # Check each variable independently
  for varIdx, v in varList.pairs:
    let segment = v.segment.toInt
    let valA = (a.segments[segment] and v.mask) shr v.shift.toInt
    let valB = (b.segments[segment] and v.mask) shr v.shift.toInt

    # All 1s in the variable's bits means DontCare
    let maxVal = (KeySegment(1) shl v.bitSize) - KeySegment(1)
    let isDontCareA = valA == maxVal
    let isDontCareB = valB == maxVal

    # Match if either is DontCare or both have same value
    if not isDontCareA and not isDontCareB and valA != valB:
      return false

  true


func matches*(a, b: Key): bool {.inline.} =
  ## Check if two keys match using bitwise DontCare semantics.
  ##
  ## Matching rules:
  ## 1. Keys must have the same number of segments
  ## 2. Identical segments always match
  ## 3. If either segment is all 1s (DontCare), it matches anything
  ## 4. Otherwise, positions match if:
  ##    - Both have 1 (both are wildcards at this position), OR
  ##    - Both have the same value (both 0 or both 1)
  ##
  ## Mathematically, for each bit position:
  ##   match = (a[i] = b[i]) OR (a[i] = 1 AND b[i] = 1)
  ##   mismatch = (a[i] ≠ b[i]) AND NOT(a[i] = 1 AND b[i] = 1)
  ##            = (a[i] XOR b[i]) AND NOT(a[i] AND b[i])
  ##
  ## A key with DontCare in a variable position (all 1s in that variable's bits)
  ## will match any value in that variable. This function cannot distinguish
  ## variable boundaries, so it treats any bit with 1 in both keys as matching.
  ##
  ## For precise per-variable matching, use matchesWithVarList.
  if a.segments.len != b.segments.len:
    return false

  for i in 0..<a.segments.len:
    let segA = a.segments[i]
    let segB = b.segments[i]

    if segA == segB:
      continue  # Identical segments always match

    # If either segment is all 1s (full DontCare), it matches anything
    if segA == DontCare or segB == DontCare:
      continue

    # Check for mismatches in non-wildcard positions
    # diff: positions where bits differ
    # bothOnes: positions where both have 1 (mutual wildcard)
    # nonWildcard: positions where at least one has 0 (defined value)
    # Mismatch occurs when diff has 1 in a nonWildcard position
    let diff = segA xor segB
    let bothOnes = segA and segB
    let nonWildcard = not bothOnes

    if (diff and nonWildcard) != KeySegment(0):
      return false

  true
