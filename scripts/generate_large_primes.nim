## Generate large prime dataset for parallel search testing
##
## Usage:
##   nim c -r -d:release scripts/generate_large_primes.nim [options]
##
## Options:
##   --start=N       Start above N (default: 1000000)
##   --limit=N       Generate primes up to N (default: 200000000)
##   --output=FILE   Output file (default: data/primes_large.json)
##   --residues=N,N  Comma-separated residue classes (default: 3,5,7,11,13,17,19)
##   --dv=N          Which residue class is the DV (default: 3)
##
## Examples:
##   # R3-R17 with 10M+ primes
##   ./scripts/generate_large_primes --limit=200000000 --residues=3,5,7,11,13,17
##
##   # R3-R19 with more primes
##   ./scripts/generate_large_primes --limit=400000000 --residues=3,5,7,11,13,17,19

import std/[os, strformat, strutils, times, json, parseopt, sequtils]
import ../src/occam/io/sequences

proc formatNum(n: int): string =
  let s = $n
  var formatted = ""
  var count = 0
  for i in countdown(s.len - 1, 0):
    if count > 0 and count mod 3 == 0:
      formatted = "," & formatted
    formatted = s[i] & formatted
    count += 1
  formatted

proc parseResidues(s: string): seq[int] =
  result = @[]
  for part in s.split(','):
    result.add(parseInt(part.strip()))

proc main() =
  var startAbove = 1_000_000
  var limit = 200_000_000
  var outputFile = "data/primes_large.json"
  var residues = @[3, 5, 7, 11, 13, 17, 19]
  var dvResidue = 3

  # Parse command line options
  var p = initOptParser()
  while true:
    p.next()
    case p.kind
    of cmdEnd: break
    of cmdShortOption, cmdLongOption:
      case p.key.toLowerAscii()
      of "start": startAbove = parseInt(p.val)
      of "limit": limit = parseInt(p.val)
      of "output": outputFile = p.val
      of "residues": residues = parseResidues(p.val)
      of "dv": dvResidue = parseInt(p.val)
      of "help", "h":
        echo "Usage: generate_large_primes [--start=N] [--limit=N] [--output=FILE] [--residues=N,N,...] [--dv=N]"
        quit(0)
    of cmdArgument:
      discard

  echo "=" .repeat(70)
  echo "LARGE PRIME DATASET GENERATOR"
  echo "=" .repeat(70)
  echo ""
  echo "Generating primes from " & formatNum(startAbove) & " to " & formatNum(limit)
  echo "Output file: " & outputFile
  echo "Residue classes: R" & residues.mapIt($it).join(", R")
  echo "DV: R" & $dvResidue
  echo ""

  # Calculate expected state space
  var stateSpace = 1
  for r in residues:
    if r != dvResidue:
      stateSpace *= (r - 1)
  let dvStateSpace = dvResidue - 1
  let totalStateSpace = stateSpace * dvStateSpace
  echo "State space (IVs only): " & formatNum(stateSpace)
  echo "State space (with DV): " & formatNum(totalStateSpace)
  echo ""

  # Generate primes
  echo "Generating primes..."
  let genStart = cpuTime()
  let primes = generatePrimesInRange(startAbove, limit)
  let genTime = cpuTime() - genStart
  echo "Generated " & formatNum(primes.len) & " primes in " & &"{genTime:.1f}s"
  echo ""

  # Check adequacy
  let obsPerCell = float(primes.len) / float(totalStateSpace)
  echo "Sample adequacy:"
  echo "  Observations: " & formatNum(primes.len)
  echo "  State space: " & formatNum(totalStateSpace)
  echo &"  Obs/cell: {obsPerCell:.1f}"
  if obsPerCell >= 10:
    echo "  Assessment: GOOD (>= 10 obs/cell)"
  elif obsPerCell >= 5:
    echo "  Assessment: MARGINAL (5-10 obs/cell)"
  else:
    echo "  Assessment: INSUFFICIENT (< 5 obs/cell)"
  echo ""

  # Build columns - all residues except DV are IVs
  var ivColumns: seq[ColumnDef]
  var abbrevIdx = 0
  for r in residues:
    if r != dvResidue:
      ivColumns.add(residueColumn(r, $chr(ord('A') + abbrevIdx)))
      abbrevIdx += 1
  let dvColumn = residueColumn(dvResidue, "Z")

  echo "Building dataset with consecutive pairs..."
  echo "  IVs: " & ivColumns.mapIt(it.name).join(", ")
  echo "  DV: " & dvColumn.name
  let buildStart = cpuTime()
  let dataset = buildConsecutivePairDataset(
    primes, ivColumns, dvColumn,
    includeValues = false,
    name = "primes_" & $startAbove & "_to_" & $limit
  )
  let buildTime = cpuTime() - buildStart
  echo "Built " & formatNum(dataset.rows.len) & &" rows in {buildTime:.1f}s"
  echo ""

  # Convert to OCCAM JSON format
  echo "Converting to OCCAM JSON format..."
  let convertStart = cpuTime()

  var occamJson = newJObject()
  occamJson["name"] = %dataset.name
  occamJson["sampleSize"] = %float(dataset.rows.len)

  # Variables
  var varsArray = newJArray()
  for i, col in dataset.columns:
    var varObj = newJObject()
    varObj["name"] = %col.name
    varObj["abbrev"] = %col.abbrev
    varObj["cardinality"] = %dataset.columnCardinalities[i]
    varObj["isDependent"] = %false
    varsArray.add(varObj)

  # Add DV
  var dvObj = newJObject()
  dvObj["name"] = %dataset.targetColumn.name
  dvObj["abbrev"] = %dataset.targetColumn.abbrev
  dvObj["cardinality"] = %dataset.dvCardinality
  dvObj["isDependent"] = %true
  varsArray.add(dvObj)

  occamJson["variables"] = varsArray

  # Data
  var dataArray = newJArray()
  for row in dataset.rows:
    var rowArray = newJArray()
    for v in row.ivValues:
      rowArray.add(%v)
    rowArray.add(%row.dvValue)
    dataArray.add(rowArray)
  occamJson["data"] = dataArray

  let convertTime = cpuTime() - convertStart
  echo &"Converted in {convertTime:.1f}s"

  # Ensure directory exists
  let dir = parentDir(outputFile)
  if dir.len > 0:
    createDir(dir)

  # Write to file
  echo "Writing to " & outputFile & "..."
  let writeStart = cpuTime()
  writeFile(outputFile, $occamJson)
  let writeTime = cpuTime() - writeStart
  echo &"Written in {writeTime:.1f}s"
  echo ""

  let totalTime = genTime + buildTime + convertTime + writeTime
  echo "=" .repeat(70)
  echo "COMPLETE: " & formatNum(dataset.rows.len) & &" rows, {totalTime:.1f}s total"
  echo "=" .repeat(70)

when isMainModule:
  main()
