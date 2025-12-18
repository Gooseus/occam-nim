## Core type definitions for OCCAM
## Uses Nim's distinct types for compile-time safety

{.push raises: [].}

type
  Cardinality* = distinct int
    ## Number of possible values for a variable (2-65535)

  KeySegment* = distinct uint32
    ## Single segment of a packed key (32 bits)

  VariableIndex* = distinct int
    ## Index into a VariableList

  RelationIndex* = distinct int
    ## Index into a Model's relation list

  BitShift* = distinct int
    ## Bit position within a key segment

  SegmentIndex* = distinct int
    ## Index into key segment array

  Direction* = enum
    ## Search direction through model lattice
    Ascending   ## Bottom-up (independence to saturation)
    Descending  ## Top-down (saturation to independence)

  TableKind* = enum
    ## Type of table data
    InformationTheoretic  ## Probability distributions (sums to 1)
    SetTheoretic          ## Binary presence/absence

  SearchFilter* = enum
    ## Model filter during search
    Full       ## All models
    Loopless   ## Only acyclic models
    Disjoint   ## Non-overlapping relations only
    Chain      ## Chain structure only

const
  DontCare* = KeySegment(0xFFFF_FFFF'u32)
    ## All bits on - indicates wildcard/don't care value

  KeySegmentBits* = 32
    ## Number of usable bits in a key segment

  MaxNameLen* = 32
    ## Maximum length of variable name

  MaxAbbrevLen* = 8
    ## Maximum length of variable abbreviation

  ProbMin* = 1e-36
    ## Minimum probability to avoid underflow

  PrintMin* = 1e-8
    ## Minimum value for printing


# Cardinality operators (borrowed from int)
proc `==`*(a, b: Cardinality): bool {.borrow.}
proc `<`*(a, b: Cardinality): bool {.borrow.}
proc `<=`*(a, b: Cardinality): bool {.borrow.}
proc `-`*(a, b: Cardinality): Cardinality {.borrow.}
proc `+`*(a, b: Cardinality): Cardinality {.borrow.}
proc `*`*(a, b: Cardinality): Cardinality {.borrow.}
proc `$`*(c: Cardinality): string {.borrow.}

func toInt*(c: Cardinality): int {.inline.} =
  ## Convert Cardinality to int
  int(c)


# KeySegment operators (borrowed from uint32)
proc `==`*(a, b: KeySegment): bool {.borrow.}
proc `<`*(a, b: KeySegment): bool {.borrow.}
proc `and`*(a, b: KeySegment): KeySegment {.borrow.}
proc `or`*(a, b: KeySegment): KeySegment {.borrow.}
proc `xor`*(a, b: KeySegment): KeySegment {.borrow.}
proc `not`*(a: KeySegment): KeySegment {.borrow.}
proc `shl`*(a: KeySegment, b: int): KeySegment {.borrow.}
proc `shr`*(a: KeySegment, b: int): KeySegment {.borrow.}
proc `-`*(a, b: KeySegment): KeySegment {.borrow.}
proc `+`*(a, b: KeySegment): KeySegment {.borrow.}

func toUint32*(k: KeySegment): uint32 {.inline.} =
  ## Convert KeySegment to uint32
  uint32(k)


# VariableIndex operators
proc `==`*(a, b: VariableIndex): bool {.borrow.}
proc `<`*(a, b: VariableIndex): bool {.borrow.}
proc `<=`*(a, b: VariableIndex): bool {.borrow.}
proc `$`*(v: VariableIndex): string {.borrow.}

func toInt*(v: VariableIndex): int {.inline.} =
  ## Convert VariableIndex to int
  int(v)

func cmp*(a, b: VariableIndex): int {.inline.} =
  ## Compare two VariableIndex values for sorting
  cmp(int(a), int(b))


# RelationIndex operators
proc `==`*(a, b: RelationIndex): bool {.borrow.}
proc `<`*(a, b: RelationIndex): bool {.borrow.}
proc `$`*(r: RelationIndex): string {.borrow.}

func toInt*(r: RelationIndex): int {.inline.} =
  ## Convert RelationIndex to int
  int(r)


# BitShift operators
proc `==`*(a, b: BitShift): bool {.borrow.}
proc `<`*(a, b: BitShift): bool {.borrow.}
proc `-`*(a, b: BitShift): BitShift {.borrow.}
proc `$`*(b: BitShift): string {.borrow.}

func toInt*(b: BitShift): int {.inline.} =
  ## Convert BitShift to int
  int(b)


# SegmentIndex operators
proc `==`*(a, b: SegmentIndex): bool {.borrow.}
proc `<`*(a, b: SegmentIndex): bool {.borrow.}
proc `+`*(a: SegmentIndex, b: int): SegmentIndex {.borrow.}
proc `$`*(s: SegmentIndex): string {.borrow.}

func toInt*(s: SegmentIndex): int {.inline.} =
  ## Convert SegmentIndex to int
  int(s)
