## Integer sequence dataset generator for OCCAM-Nim
## Generates datasets from integer sequences (primes, naturals, etc.) with configurable columns
## This module is PURE - no OCCAM dependencies, can be used standalone

{.push raises: [].}

import std/[options, strutils, sequtils, math, tables, json]
import primes

type
  SequenceKind* = enum
    skPrimes        ## Prime numbers (uses primes.below())
    skNaturals      ## Natural numbers (1, 2, 3, ...)
    skOdds          ## Odd numbers (1, 3, 5, ...)
    skCustom        ## User-provided sequence

  ColumnKind* = enum
    ckResidue        ## n mod base
    ckCollatzDist    ## Steps to reach 1 in Collatz sequence
    ckDigitSum       ## Sum of decimal digits
    ckPrimeFactor    ## Number of prime factors (with multiplicity)
    ckCustom         ## User-provided function

  ColumnDef* = object
    name*: string           ## Column name (e.g., "R3", "collatz")
    abbrev*: string         ## Single-letter abbreviation for OCCAM
    case kind*: ColumnKind
    of ckResidue:
      base*: int            ## The modulus (e.g., 3, 5, 7)
    of ckCollatzDist:
      maxSteps*: int        ## Cap to prevent runaway
    of ckDigitSum, ckPrimeFactor:
      discard
    of ckCustom:
      compute*: proc(n: int): int

  DataRow* = object
    ivValues*: seq[int]             ## Column values for n (or prev in pair)
    dvValue*: int                   ## Target column value for n+1 (or next in pair)
    sourceValues*: Option[(int, int)]  ## Optional: actual (n, n+1) values

  SequenceDataset* = object
    name*: string
    columns*: seq[ColumnDef]    ## All columns (IVs)
    targetColumn*: ColumnDef    ## The DV column
    rows*: seq[DataRow]         ## All data rows
    columnCardinalities*: seq[int]  ## Observed cardinalities for each IV column
    dvCardinality*: int             ## Observed cardinality for DV


# ============ Sequence Generators ============

proc generatePrimes*(limit: int): seq[int] {.raises: [ValueError].} =
  ## Generate all primes below limit using the primes package
  result = primes.below(limit)


proc generatePrimesInRange*(start: int; limit: int): seq[int] {.raises: [ValueError].} =
  ## Generate all primes in range [start, limit)
  let allPrimes = primes.below(limit)
  result = @[]
  for p in allPrimes:
    if p >= start:
      result.add(p)


proc generatePrimesCount*(count: int): seq[int] {.raises: [ValueError].} =
  ## Generate approximately `count` primes by estimating the upper bound
  ## Uses prime number theorem: pi(n) ~ n / ln(n)
  if count <= 0:
    return @[]
  if count < 10:
    # Small counts - just use a fixed limit
    result = primes.below(100)
    if result.len > count:
      result = result[0..<count]
    return

  # Estimate upper bound using prime number theorem with safety margin
  let estimated = int(float(count) * (ln(float(count)) + ln(ln(float(count))) + 2.0))
  result = primes.below(estimated)
  if result.len > count:
    result = result[0..<count]


proc generateNaturals*(start: int; count: int): seq[int] =
  ## Generate `count` natural numbers starting from `start`
  result = newSeq[int](count)
  for i in 0..<count:
    result[i] = start + i


proc generateOdds*(start: int; count: int): seq[int] =
  ## Generate `count` odd numbers starting from or after `start`
  result = newSeq[int](count)
  var current = if start mod 2 == 0: start + 1 else: start
  for i in 0..<count:
    result[i] = current
    current += 2


proc generateSequence*(kind: SequenceKind; limit: int = 0; count: int = 0;
                       start: int = 0; customSeq: seq[int] = @[]): seq[int] {.raises: [ValueError].} =
  ## Generate a sequence based on kind and parameters
  ## If start > 0, only include values >= start
  case kind
  of skPrimes:
    if count > 0:
      result = generatePrimesCount(count)
      if start > 0:
        result = result.filterIt(it >= start)
    elif limit > 0:
      if start > 0:
        result = generatePrimesInRange(start, limit)
      else:
        result = generatePrimes(limit)
    else:
      raise newException(ValueError, "Must specify limit or count for primes")
  of skNaturals:
    let actualStart = if start > 0: start else: 1
    if count > 0:
      result = generateNaturals(actualStart, count)
    elif limit > 0:
      result = generateNaturals(actualStart, limit - actualStart + 1)
    else:
      raise newException(ValueError, "Must specify limit or count for naturals")
  of skOdds:
    let actualStart = if start > 0: start else: 1
    if count > 0:
      result = generateOdds(actualStart, count)
    elif limit > 0:
      result = generateOdds(actualStart, (limit - actualStart) div 2 + 1)
    else:
      raise newException(ValueError, "Must specify limit or count for odds")
  of skCustom:
    result = customSeq
    if start > 0:
      result = result.filterIt(it >= start)


# ============ Column Generators ============

proc computeCollatzSteps*(n: int; maxSteps: int = 1000): int =
  ## Compute number of steps in Collatz sequence to reach 1
  if n <= 1:
    return 0
  var current = n
  var steps = 0
  while current != 1 and steps < maxSteps:
    if current mod 2 == 0:
      current = current div 2
    else:
      current = 3 * current + 1
    steps += 1
  result = steps


proc computeDigitSum*(n: int): int =
  ## Sum of decimal digits
  var current = abs(n)
  result = 0
  while current > 0:
    result += current mod 10
    current = current div 10


proc countPrimeFactors*(n: int): int =
  ## Count prime factors with multiplicity
  if n <= 1:
    return 0
  var current = n
  result = 0
  var d = 2
  while d * d <= current:
    while current mod d == 0:
      result += 1
      current = current div d
    d += 1
  if current > 1:
    result += 1


proc computeColumn*(col: ColumnDef; n: int): int =
  ## Compute column value for a given integer
  case col.kind
  of ckResidue:
    result = n mod col.base
  of ckCollatzDist:
    result = computeCollatzSteps(n, col.maxSteps)
  of ckDigitSum:
    result = computeDigitSum(n)
  of ckPrimeFactor:
    result = countPrimeFactors(n)
  of ckCustom:
    result = col.compute(n)


# ============ Column Constructors ============

proc residueColumn*(base: int; abbrev: string = ""): ColumnDef =
  ## Create a residue class column (n mod base)
  let name = "R" & $base
  let ab = if abbrev.len > 0: abbrev else: name
  result = ColumnDef(
    kind: ckResidue,
    name: name,
    abbrev: ab,
    base: base
  )


proc collatzColumn*(maxSteps: int = 1000; abbrev: string = "K"): ColumnDef =
  ## Create a Collatz distance column
  result = ColumnDef(
    kind: ckCollatzDist,
    name: "collatz",
    abbrev: abbrev,
    maxSteps: maxSteps
  )


proc digitSumColumn*(abbrev: string = "D"): ColumnDef =
  ## Create a digit sum column
  result = ColumnDef(
    kind: ckDigitSum,
    name: "digits",
    abbrev: abbrev
  )


proc primeFactorCountColumn*(abbrev: string = "F"): ColumnDef =
  ## Create a prime factor count column
  result = ColumnDef(
    kind: ckPrimeFactor,
    name: "factors",
    abbrev: abbrev
  )


proc customColumn*(name: string; abbrev: string;
                   compute: proc(n: int): int): ColumnDef =
  ## Create a custom column with user-provided compute function
  result = ColumnDef(
    kind: ckCustom,
    name: name,
    abbrev: abbrev,
    compute: compute
  )


proc defaultModuli*(): seq[int] =
  ## Default set of residue class moduli
  @[3, 5, 7, 11, 13]


proc residueColumns*(bases: seq[int]): seq[ColumnDef] =
  ## Create residue columns for a list of bases
  result = @[]
  for i, base in bases:
    # Assign single-letter abbreviations: A, B, C, ...
    let abbrev = $(char(ord('A') + i))
    result.add(residueColumn(base, abbrev))


# ============ Column Parsing ============

proc parseColumnSpec*(spec: string; abbrev: string = ""): ColumnDef {.raises: [ValueError].} =
  ## Parse a column specification string
  ## Supported formats:
  ##   R3, R5, R11, etc. - residue classes
  ##   collatz - Collatz distance
  ##   digits - digit sum
  ##   factors - prime factor count
  let s = spec.strip().toLowerAscii()

  if s.startsWith("r") and s.len > 1:
    try:
      let base = parseInt(s[1..^1])
      result = residueColumn(base, abbrev)
    except ValueError:
      raise newException(ValueError, "Invalid residue column spec: " & spec)
  elif s == "collatz":
    result = collatzColumn(abbrev = if abbrev.len > 0: abbrev else: "K")
  elif s == "digits":
    result = digitSumColumn(abbrev = if abbrev.len > 0: abbrev else: "D")
  elif s == "factors":
    result = primeFactorCountColumn(abbrev = if abbrev.len > 0: abbrev else: "F")
  else:
    raise newException(ValueError, "Unknown column spec: " & spec)


proc parseColumnsSpec*(specs: string): seq[ColumnDef] {.raises: [ValueError].} =
  ## Parse comma-separated column specifications
  ## Assigns single-letter abbreviations A, B, C, ... automatically
  result = @[]
  let parts = specs.split(',')
  for i, part in parts:
    let abbrev = $(char(ord('A') + i))
    result.add(parseColumnSpec(part.strip(), abbrev))


# ============ Dataset Builders ============

proc buildConsecutivePairDataset*(
  sequence: seq[int];
  ivColumns: seq[ColumnDef];
  dvColumn: ColumnDef;
  includeValues: bool = false;
  name: string = "sequence_dataset"
): SequenceDataset =
  ## Build a dataset from consecutive pairs in the sequence
  ## IVs are computed from n, DV is computed from n+1
  result.name = name
  result.columns = ivColumns
  result.targetColumn = dvColumn
  result.rows = @[]

  # Track observed values for cardinality computation
  var ivValueSets = newSeq[CountTable[int]](ivColumns.len)
  for i in 0..<ivColumns.len:
    ivValueSets[i] = initCountTable[int]()
  var dvValueSet = initCountTable[int]()

  # Process consecutive pairs
  for i in 0..<(sequence.len - 1):
    let n = sequence[i]
    let nNext = sequence[i + 1]

    var row: DataRow
    row.ivValues = @[]

    # Compute IV column values for n
    for j, col in ivColumns:
      let val = computeColumn(col, n)
      row.ivValues.add(val)
      ivValueSets[j].inc(val)

    # Compute DV column value for n+1
    row.dvValue = computeColumn(dvColumn, nNext)
    dvValueSet.inc(row.dvValue)

    # Optionally store source values
    if includeValues:
      row.sourceValues = some((n, nNext))

    result.rows.add(row)

  # Compute observed cardinalities
  result.columnCardinalities = @[]
  for vs in ivValueSets:
    result.columnCardinalities.add(vs.len)
  result.dvCardinality = dvValueSet.len


proc buildSingleRowDataset*(
  sequence: seq[int];
  columns: seq[ColumnDef];
  dvColumnIndex: int;
  includeValues: bool = false;
  name: string = "sequence_dataset"
): SequenceDataset {.raises: [ValueError].} =
  ## Build a dataset where each number in the sequence is one row
  ## One of the columns is designated as the DV
  if dvColumnIndex < 0 or dvColumnIndex >= columns.len:
    raise newException(ValueError, "Invalid dvColumnIndex: " & $dvColumnIndex)

  result.name = name
  result.targetColumn = columns[dvColumnIndex]

  # Build IV columns (all except DV)
  result.columns = @[]
  for i, col in columns:
    if i != dvColumnIndex:
      result.columns.add(col)

  result.rows = @[]

  # Track observed values for cardinality computation
  var ivValueSets = newSeq[CountTable[int]](result.columns.len)
  for i in 0..<result.columns.len:
    ivValueSets[i] = initCountTable[int]()
  var dvValueSet = initCountTable[int]()

  # Process each number
  for n in sequence:
    var row: DataRow
    row.ivValues = @[]

    var ivIdx = 0
    for i, col in columns:
      let val = computeColumn(col, n)
      if i == dvColumnIndex:
        row.dvValue = val
        dvValueSet.inc(val)
      else:
        row.ivValues.add(val)
        ivValueSets[ivIdx].inc(val)
        ivIdx += 1

    if includeValues:
      row.sourceValues = some((n, n))

    result.rows.add(row)

  # Compute observed cardinalities
  result.columnCardinalities = @[]
  for vs in ivValueSets:
    result.columnCardinalities.add(vs.len)
  result.dvCardinality = dvValueSet.len


# ============ Output Formatters ============

proc toCSV*(ds: SequenceDataset; includeHeader: bool = true): string =
  ## Convert dataset to CSV string
  var lines: seq[string] = @[]

  # Header
  if includeHeader:
    var headerParts: seq[string] = @[]
    for col in ds.columns:
      headerParts.add(col.name)
    headerParts.add(ds.targetColumn.name)
    lines.add(headerParts.join(","))

  # Data rows
  for row in ds.rows:
    var parts: seq[string] = @[]
    for v in row.ivValues:
      parts.add($v)
    parts.add($row.dvValue)
    lines.add(parts.join(","))

  result = lines.join("\n")


proc toGenericJSON*(ds: SequenceDataset): string =
  ## Convert dataset to generic JSON format (not OCCAM-specific)
  var obj = newJObject()
  obj["name"] = %ds.name

  # Columns
  var colsArray = newJArray()
  for col in ds.columns:
    var colObj = newJObject()
    colObj["name"] = %col.name
    colObj["abbrev"] = %col.abbrev
    colObj["kind"] = %($col.kind)
    colsArray.add(colObj)
  obj["columns"] = colsArray

  # Target column
  var targetObj = newJObject()
  targetObj["name"] = %ds.targetColumn.name
  targetObj["abbrev"] = %ds.targetColumn.abbrev
  targetObj["kind"] = %($ds.targetColumn.kind)
  obj["targetColumn"] = targetObj

  # Cardinalities
  obj["columnCardinalities"] = %ds.columnCardinalities
  obj["dvCardinality"] = %ds.dvCardinality

  # Data
  var dataArray = newJArray()
  for row in ds.rows:
    var rowArray = newJArray()
    for v in row.ivValues:
      rowArray.add(%v)
    rowArray.add(%row.dvValue)
    dataArray.add(rowArray)
  obj["data"] = dataArray

  result = $obj


# ============ Utility Functions ============

proc getColumnCardinality*(col: ColumnDef; forPrimes: bool = true): int =
  ## Get the expected cardinality for a column type
  ## For residue classes, this depends on whether we're working with primes
  case col.kind
  of ckResidue:
    if forPrimes and col.base > 2:
      # For primes > base, residues are phi(base) = base-1 for prime base
      # (0 is never a valid residue for primes > base)
      result = col.base - 1
    else:
      result = col.base
  of ckCollatzDist:
    result = col.maxSteps + 1  # 0 to maxSteps
  of ckDigitSum:
    result = 100  # Arbitrary, will be determined from data
  of ckPrimeFactor:
    result = 20  # Arbitrary, most numbers have < 20 prime factors
  of ckCustom:
    result = 100  # Unknown, must be determined from data


proc summary*(ds: SequenceDataset): string =
  ## Return a human-readable summary of the dataset
  var lines: seq[string] = @[]
  lines.add("Dataset: " & ds.name)
  lines.add("Rows: " & $ds.rows.len)
  lines.add("IV Columns:")
  for i, col in ds.columns:
    lines.add("  " & col.name & " (" & col.abbrev & ") - cardinality: " &
              $ds.columnCardinalities[i])
  lines.add("DV Column: " & ds.targetColumn.name & " (" &
            ds.targetColumn.abbrev & ") - cardinality: " & $ds.dvCardinality)
  result = lines.join("\n")


# ============ Sample Size Adequacy ============

type
  SampleAdequacy* = object
    stateSpace*: int          ## Total cells in contingency table
    sampleSize*: int          ## Number of observations
    obsPerCell*: float        ## Average observations per cell
    minRequired*: int         ## Minimum N for chi-squared validity (5/cell)
    recommendedN*: int        ## Recommended N for reliable estimates (10/cell)
    isAdequate*: bool         ## Whether sample size is sufficient
    coverage*: float          ## Estimated coverage (N / stateSpace)
    assessment*: string       ## Human-readable assessment


proc computeStateSpace*(cardinalities: seq[int]): int =
  ## Compute total state space (product of cardinalities)
  result = 1
  for c in cardinalities:
    result *= c


proc computeStateSpaceForPrimeResidues*(bases: seq[int]): int =
  ## Compute state space for prime residue analysis
  ## For primes > base, residues are 1..(base-1), so cardinality = base-1
  result = 1
  for base in bases:
    result *= (base - 1)  # phi(prime) = prime - 1


proc assessSampleAdequacy*(sampleSize: int; cardinalities: seq[int];
                           minPerCell: float = 5.0): SampleAdequacy =
  ## Assess whether sample size is adequate for the given state space
  result.stateSpace = computeStateSpace(cardinalities)
  result.sampleSize = sampleSize
  result.obsPerCell = float(sampleSize) / float(result.stateSpace)
  result.minRequired = int(minPerCell * float(result.stateSpace))
  result.recommendedN = int(10.0 * float(result.stateSpace))
  result.isAdequate = result.obsPerCell >= minPerCell
  result.coverage = float(sampleSize) / float(result.stateSpace)

  if result.obsPerCell >= 100:
    result.assessment = "Excellent - highly reliable estimates"
  elif result.obsPerCell >= 20:
    result.assessment = "Very good - reliable estimates"
  elif result.obsPerCell >= 10:
    result.assessment = "Good - adequate for most analyses"
  elif result.obsPerCell >= 5:
    result.assessment = "Marginal - chi-squared valid but estimates may be unstable"
  elif result.obsPerCell >= 1:
    result.assessment = "Insufficient - sparse data, unreliable estimates"
  else:
    result.assessment = "Severely insufficient - most cells will be empty"


proc maxResidueClasses*(sampleSize: int; targetObsPerCell: float = 10.0): int =
  ## Calculate maximum number of small prime residue classes analyzable
  ## Uses primes 3, 5, 7, 11, 13, 17, 19, 23, ... with cardinalities 2, 4, 6, 10, 12, 16, 18, 22, ...
  let smallPrimes = @[3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
  var stateSpace = 1
  result = 0
  for p in smallPrimes:
    let newStateSpace = stateSpace * (p - 1)
    if float(sampleSize) / float(newStateSpace) >= targetObsPerCell:
      stateSpace = newStateSpace
      result += 1
    else:
      break


proc printAdequacyTable*(sampleSize: int; maxVars: int = 8) =
  ## Print a table showing state space growth and adequacy for prime residues
  let smallPrimes = @[3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
  echo "Sample Size: " & $sampleSize
  echo ""
  echo "IVs          State Space    Obs/Cell    Assessment"
  echo "-".repeat(65)

  var stateSpace = 1
  var ivList: seq[string] = @[]
  for i in 0..<min(maxVars, smallPrimes.len):
    let p = smallPrimes[i]
    stateSpace *= (p - 1)
    # Include DV cardinality (2 for mod 3)
    let fullStateSpace = stateSpace * 2
    ivList.add("R" & $p)
    let obsPerCell = float(sampleSize) / float(fullStateSpace)

    var assessment: string
    if obsPerCell >= 100:
      assessment = "Excellent"
    elif obsPerCell >= 20:
      assessment = "Very good"
    elif obsPerCell >= 10:
      assessment = "Good"
    elif obsPerCell >= 5:
      assessment = "Marginal"
    elif obsPerCell >= 1:
      assessment = "Insufficient"
    else:
      assessment = "Severely insufficient"

    let ivStr = ivList.join(",")
    echo ivStr.alignLeft(12) & " " &
         ($fullStateSpace).alignLeft(14) & " " &
         obsPerCell.formatFloat(ffDecimal, 1).alignLeft(11) & " " &
         assessment


proc requiredSampleSize*(numResidueClasses: int; targetObsPerCell: float = 10.0): int =
  ## Calculate required sample size for a given number of prime residue classes
  let smallPrimes = @[3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
  var stateSpace = 1
  for i in 0..<min(numResidueClasses, smallPrimes.len):
    stateSpace *= (smallPrimes[i] - 1)
  # Include DV cardinality (2 for mod 3)
  stateSpace *= 2
  result = int(float(stateSpace) * targetObsPerCell)


proc printRequiredSamplesTable*(maxVars: int = 10; targetObsPerCell: float = 10.0) =
  ## Print a table showing required sample sizes for different numbers of residue classes
  let smallPrimes = @[3, 5, 7, 11, 13, 17, 19, 23, 29, 31, 37, 41, 43, 47]
  echo "Required Samples for " & $int(targetObsPerCell) & " obs/cell:"
  echo ""
  echo "IVs                    State Space    Required N       Est. Prime Limit"
  echo "-".repeat(75)

  var stateSpace = 1
  var ivList: seq[string] = @[]
  for i in 0..<min(maxVars, smallPrimes.len):
    let p = smallPrimes[i]
    stateSpace *= (p - 1)
    # Include DV cardinality (2 for mod 3)
    let fullStateSpace = stateSpace * 2
    ivList.add("R" & $p)
    let requiredN = int(float(fullStateSpace) * targetObsPerCell)

    # Estimate prime limit using prime number theorem: π(n) ≈ n / ln(n)
    # We need requiredN primes, so solve n/ln(n) ≈ requiredN
    # Approximation: n ≈ requiredN * (ln(requiredN) + ln(ln(requiredN)))
    var estLimit: string
    if requiredN < 100:
      estLimit = "< 1,000"
    else:
      let lnN = ln(float(requiredN))
      let est = float(requiredN) * (lnN + ln(lnN))
      if est < 1e6:
        estLimit = formatFloat(est / 1000.0, ffDecimal, 0) & "K"
      elif est < 1e9:
        estLimit = formatFloat(est / 1e6, ffDecimal, 1) & "M"
      elif est < 1e12:
        estLimit = formatFloat(est / 1e9, ffDecimal, 1) & "B"
      else:
        estLimit = formatFloat(est / 1e12, ffDecimal, 1) & "T"

    let ivStr = ivList.join(",")

    # Format requiredN with commas
    var reqStr = $requiredN
    var formatted = ""
    var count = 0
    for j in countdown(reqStr.len - 1, 0):
      if count > 0 and count mod 3 == 0:
        formatted = "," & formatted
      formatted = reqStr[j] & formatted
      count += 1

    echo ivStr.alignLeft(22) & " " &
         ($fullStateSpace).alignLeft(14) & " " &
         formatted.alignLeft(16) & " " &
         estLimit
