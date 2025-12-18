## Sequence dataset helpers for e2e tests
## Generates and caches integer sequence datasets for testing

import std/[os, strutils, strformat]
import ../../src/occam/io/sequences
import ../../src/occam/io/sequences_occam
import ../../src/occam/io/parser

const
  FixturesDir* = currentSourcePath.parentDir.parentDir / "fixtures" / "sequences"


proc ensurePrimeResidueDataset*(
  limit: int = 100000;
  moduli: seq[int] = @[3, 5, 7];
  targetModulus: int = 3
): string =
  ## Ensure prime residue dataset exists, generating if needed.
  ## Returns path to JSON file.

  # Create fixtures directory if needed
  if not dirExists(FixturesDir):
    createDir(FixturesDir)

  # Build filename based on parameters
  let moduliStr = moduli.join("_")
  let fileName = &"primes_{limit}_R{moduliStr}_target{targetModulus}.json"
  let jsonPath = FixturesDir / fileName

  if not fileExists(jsonPath):
    echo "Generating prime residue dataset: ", jsonPath

    # Generate primes
    let primeSeq = generatePrimes(limit)
    echo "  Generated ", primeSeq.len, " primes"

    # Create IV columns for each modulus
    var ivColumns: seq[ColumnDef] = @[]
    for i, m in moduli:
      let abbrev = $(char(ord('A') + i))
      ivColumns.add(residueColumn(m, abbrev))

    # Create DV column
    let dvColumn = residueColumn(targetModulus, "Z")

    # Build dataset
    let ds = buildConsecutivePairDataset(primeSeq, ivColumns, dvColumn,
                                         includeValues = false,
                                         name = &"primes_R{moduliStr}")

    echo "  Rows: ", ds.rows.len

    # Save as OCCAM JSON
    let jsonContent = ds.toOccamJSON()
    writeFile(jsonPath, jsonContent)
    echo "  Saved to: ", jsonPath

  result = jsonPath


proc ensureNaturalResidueDataset*(
  count: int = 50000;
  moduli: seq[int] = @[3, 5, 7];
  targetModulus: int = 3
): string =
  ## Ensure natural number residue dataset exists, generating if needed.
  ## Returns path to JSON file.

  # Create fixtures directory if needed
  if not dirExists(FixturesDir):
    createDir(FixturesDir)

  # Build filename based on parameters
  let moduliStr = moduli.join("_")
  let fileName = &"naturals_{count}_R{moduliStr}_target{targetModulus}.json"
  let jsonPath = FixturesDir / fileName

  if not fileExists(jsonPath):
    echo "Generating natural number residue dataset: ", jsonPath

    # Generate naturals
    let naturalSeq = generateNaturals(1, count)
    echo "  Generated ", naturalSeq.len, " numbers"

    # Create IV columns for each modulus
    var ivColumns: seq[ColumnDef] = @[]
    for i, m in moduli:
      let abbrev = $(char(ord('A') + i))
      ivColumns.add(residueColumn(m, abbrev))

    # Create DV column
    let dvColumn = residueColumn(targetModulus, "Z")

    # Build dataset
    let ds = buildConsecutivePairDataset(naturalSeq, ivColumns, dvColumn,
                                         includeValues = false,
                                         name = &"naturals_R{moduliStr}")

    echo "  Rows: ", ds.rows.len

    # Save as OCCAM JSON
    let jsonContent = ds.toOccamJSON()
    writeFile(jsonPath, jsonContent)
    echo "  Saved to: ", jsonPath

  result = jsonPath


proc loadSequenceDataset*(path: string): DataSpec =
  ## Load a sequence dataset from JSON file
  result = loadDataSpec(path)


proc getSequenceDatasetInfo*(name: string): tuple[description: string, expectedBias: bool] =
  ## Get expected information about a sequence dataset
  case name
  of "primes":
    result = (
      description: "Consecutive prime pairs with residue classes",
      expectedBias: true  # Lemke Oliver-Soundararajan bias expected
    )
  of "naturals":
    result = (
      description: "Consecutive natural number pairs with residue classes",
      expectedBias: false  # No bias expected for deterministic cycle
    )
  else:
    result = (description: "Unknown sequence", expectedBias: false)
