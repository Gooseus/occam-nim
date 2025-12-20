## Tests for legacy OCCAM .in format parsing
##
## Validates:
## - Variable type parsing (0=excluded, 1=IV, 2=DV)
## - Exclusion of type=0 variables in conversion
## - Frontmatter option parsing
##
## Run with: nim c -r tests/test_in_format.nim

import std/[strutils, json]
import unittest
import ../src/occam/io/formats

const
  # Sample .in content with mixed variable types
  SampleInContent = """
:action
search

:nominal
AGE2,3,0,a
EDYRS2,3,1,b
RACEAA2,2,0,c
INCOME2,3,1,d
LBW2,2,2,z

:optimize-search-width
5

:search-levels
10

:no-frequency

:data
3 2 2 2 1
1 1 1 1 2
2 3 2 3 1
"""

  # Simple .in content with all active variables
  SimpleInContent = """
:action
fit

:nominal
soft,3,1,a
previous,2,1,b
temp,2,1,c
prefer,2,2,d

:short-model
AB:BC:CD

:data
1 1 1 1  19
2 1 1 1  23
3 1 1 1  24
1 2 1 1  29
"""


suite "Legacy .in Format Parsing":

  test "parses variable types correctly":
    let parsed = parseOccamIn(SampleInContent)

    check parsed.variables.len == 5
    check parsed.variables[0].varType == vtExcluded  # AGE2: type=0
    check parsed.variables[1].varType == vtIV        # EDYRS2: type=1
    check parsed.variables[2].varType == vtExcluded  # RACEAA2: type=0
    check parsed.variables[3].varType == vtIV        # INCOME2: type=1
    check parsed.variables[4].varType == vtDV        # LBW2: type=2

  test "identifies DV correctly":
    let parsed = parseOccamIn(SampleInContent)

    check parsed.variables[0].isDependent == false
    check parsed.variables[1].isDependent == false
    check parsed.variables[4].isDependent == true  # LBW2 is DV

  test "counts active variables correctly":
    let parsed = parseOccamIn(SampleInContent)

    # 5 total, 2 excluded (type=0), so 3 active
    check parsed.activeVariableCount == 3

  test "filters active variables correctly":
    let parsed = parseOccamIn(SampleInContent)
    let active = parsed.activeVariables

    check active.len == 3
    check active[0].name == "EDYRS2"
    check active[1].name == "INCOME2"
    check active[2].name == "LBW2"

  test "parses frontmatter options":
    let parsed = parseOccamIn(SampleInContent)

    check parsed.action == "search"
    check parsed.searchWidth == 5
    check parsed.searchLevels == 10
    check parsed.hasFrequency == false  # :no-frequency flag

  test "parses fit action with model":
    let parsed = parseOccamIn(SimpleInContent)

    check parsed.action == "fit"
    check parsed.shortModel == "AB:BC:CD"
    check parsed.hasFrequency == true  # no :no-frequency flag

  test "parses data rows with frequency":
    let parsed = parseOccamIn(SimpleInContent)

    check parsed.data.len == 4
    check parsed.counts.len == 4
    check parsed.counts[0] == 19.0
    check parsed.counts[1] == 23.0
    check parsed.data[0] == @["1", "1", "1", "1"]


suite "JSON Conversion with Type=0 Exclusion":

  test "toJson excludes type=0 variables by default":
    let parsed = parseOccamIn(SampleInContent)
    let jsonStr = parsed.toJson()
    let js = parseJson(jsonStr)

    # Should have 3 active variables, not 5
    check js["variables"].len == 3
    check js["variables"][0]["name"].getStr == "EDYRS2"
    check js["variables"][1]["name"].getStr == "INCOME2"
    check js["variables"][2]["name"].getStr == "LBW2"

  test "toJson filters data columns for excluded variables":
    let parsed = parseOccamIn(SampleInContent)
    let jsonStr = parsed.toJson()
    let js = parseJson(jsonStr)

    # Data should have 3 columns (b, d, z), not 5
    check js["data"][0].len == 3
    # First row: 3 2 2 2 1 -> should become 2 2 1 (columns 1, 3, 4 in 0-indexed)
    check js["data"][0][0].getStr == "2"  # EDYRS2 value
    check js["data"][0][1].getStr == "2"  # INCOME2 value
    check js["data"][0][2].getStr == "1"  # LBW2 value

  test "toJson can include all variables when excludeType0=false":
    let parsed = parseOccamIn(SampleInContent)
    let jsonStr = parsed.toJson(excludeType0 = false)
    let js = parseJson(jsonStr)

    # Should have all 5 variables
    check js["variables"].len == 5
    check js["data"][0].len == 5


suite "State Space Calculation with Exclusion":

  test "state space matches legacy OCCAM (bw21t08 example)":
    # bw21t08.in has 15 variables but only 8 active (7 IVs + 1 DV)
    # Active: EDYRS2(3), INCOME2(3), PARTNR2(4), OTHER2(3), ESTEEM3(3), BMRISK2(3), SMOKE2(3), LBW2(2)
    # State space = 3*3*4*3*3*3*3*2 = 5832

    let content = """
:nominal
AGE2,3,0,a
EDYRS2,3,1,b
RACEAA2,2,0,c
INCOME2,3,1,d
STRESS2,3,0,e
PARTNR2,4,1,f
OTHER2,3,1,g
ESTEEM3,3,1,h
BMRISK2,3,1,i
SMOKE2,3,1,j
MARIJ2,2,0,k
ALCO2,2,0,l
DRUGS2,2,0,m
ABUSE2,2,0,n
LBW2,2,2,z

:data
3 2 2 2 2 1 3 2 2 1 1 1 1 1 1
"""

    let parsed = parseOccamIn(content)

    # Total: 15 variables, 7 excluded (type=0), 8 active
    check parsed.variables.len == 15
    check parsed.activeVariableCount == 8

    # Calculate state space for active variables
    var stateSpace = 1
    for v in parsed.activeVariables:
      stateSpace *= v.cardinality

    check stateSpace == 5832  # Matches legacy OCCAM


when isMainModule:
  echo "Running .in format tests..."
  echo ""
