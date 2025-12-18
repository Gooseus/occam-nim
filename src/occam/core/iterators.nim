## State enumeration iterators for OCCAM
##
## Provides iterators for enumerating all state combinations
## given a sequence of cardinalities.

{.push raises: [].}

iterator stateEnumeration*(cardinalities: seq[int]): seq[int] =
  ## Enumerate all state combinations for the given cardinalities.
  ##
  ## Example:
  ##   for state in stateEnumeration(@[2, 3]):
  ##     echo state  # Yields: @[0,0], @[1,0], @[0,1], @[1,1], @[0,2], @[1,2]
  ##
  ## The iteration order is "odometer style" with the first variable
  ## being the "fastest" - it increments first before carrying to the next.
  ##
  ## Total iterations = product of all cardinalities.
  if cardinalities.len == 0:
    yield @[]
  else:
    var indices = newSeq[int](cardinalities.len)
    var done = false

    while not done:
      yield indices

      # Increment with carry (odometer style)
      var carry = true
      for i in 0..<cardinalities.len:
        if carry:
          indices[i] += 1
          if indices[i] >= cardinalities[i]:
            indices[i] = 0
          else:
            carry = false
      if carry:
        done = true


iterator stateEnumerationReverse*(cardinalities: seq[int]): seq[int] =
  ## Enumerate all state combinations with last variable being fastest.
  ##
  ## Example:
  ##   for state in stateEnumerationReverse(@[2, 3]):
  ##     echo state  # Yields: @[0,0], @[0,1], @[0,2], @[1,0], @[1,1], @[1,2]
  ##
  ## This matches the ordering typically used in OCCAM output.
  if cardinalities.len == 0:
    yield @[]
  else:
    var indices = newSeq[int](cardinalities.len)
    var done = false

    while not done:
      yield indices

      # Increment with carry (last variable fastest)
      var carry = true
      for i in countdown(cardinalities.len - 1, 0):
        if carry:
          indices[i] += 1
          if indices[i] >= cardinalities[i]:
            indices[i] = 0
          else:
            carry = false
      if carry:
        done = true


proc totalStates*(cardinalities: seq[int]): int =
  ## Calculate total number of states (product of cardinalities).
  result = 1
  for c in cardinalities:
    result *= c


proc stateToIndex*(state: seq[int]; cardinalities: seq[int]): int =
  ## Convert a state vector to a linear index (first variable fastest).
  ##
  ## Example:
  ##   stateToIndex(@[1, 0], @[2, 3]) = 1
  ##   stateToIndex(@[0, 1], @[2, 3]) = 2
  result = 0
  var stride = 1
  for i in 0..<state.len:
    result += state[i] * stride
    stride *= cardinalities[i]


proc indexToState*(index: int; cardinalities: seq[int]): seq[int] =
  ## Convert a linear index to a state vector (first variable fastest).
  ##
  ## Example:
  ##   indexToState(1, @[2, 3]) = @[1, 0]
  ##   indexToState(2, @[2, 3]) = @[0, 1]
  result = newSeq[int](cardinalities.len)
  var remaining = index
  for i in 0..<cardinalities.len:
    result[i] = remaining mod cardinalities[i]
    remaining = remaining div cardinalities[i]
