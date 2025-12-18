## Tests for format conversion utilities

import std/[strutils, sequtils]
import unittest
import ../src/occam/io/formats


suite "OCCAM .in format parsing":

  test "parse simple .in file":
    let content = """
:action
search

:nominal
soft,3,1,a
previous,2,1,b
temp,2,1,c
prefer,2,1,d

:data
 1 1 1 1  19
 2 1 1 1  23
 3 1 1 1  24
"""
    let parsed = parseOccamIn(content)

    check parsed.action == "search"
    check parsed.variables.len == 4
    check parsed.hasFrequency == true

    # Check first variable
    check parsed.variables[0].name == "soft"
    check parsed.variables[0].cardinality == 3
    check parsed.variables[0].isDependent == false
    check parsed.variables[0].abbrev == "a"

    # Check data
    check parsed.data.len == 3
    check parsed.counts.len == 3
    check parsed.counts[0] == 19.0
    check parsed.counts[1] == 23.0

  test "parse .in with dependent variable":
    let content = """
:action
fit

:nominal
income,3,1,I
education,4,1,E
health,2,2,H

:data
1 1 1 50
2 2 2 30
"""
    let parsed = parseOccamIn(content)

    check parsed.variables.len == 3
    check parsed.variables[0].isDependent == false
    check parsed.variables[1].isDependent == false
    check parsed.variables[2].isDependent == true
    check parsed.variables[2].name == "health"

  test "parse .in with no-frequency flag":
    let content = """
:action
search

:nominal
A,2,1,A
B,3,1,B

:no-frequency

:data
0 0
0 1
0 2
1 0
1 1
"""
    let parsed = parseOccamIn(content)

    check parsed.hasFrequency == false
    check parsed.data.len == 5
    check parsed.counts.len == 5
    # Each row should count as 1
    for c in parsed.counts:
      check c == 1.0

  test "parse .in with search parameters":
    let content = """
:action
search

:nominal
A,2,1,A
B,2,1,B

:short-model
AB

:optimize-search-width
5

:search-levels
10

:data
0 0 10
1 1 20
"""
    let parsed = parseOccamIn(content)

    check parsed.shortModel == "AB"
    check parsed.searchWidth == 5
    check parsed.searchLevels == 10


suite "Value inference":

  test "infer values from data":
    let content = """
:action
search

:nominal
color,0,1,C
size,0,1,S

:data
red small 10
red large 15
blue small 20
blue large 25
green small 30
"""
    var parsed = parseOccamIn(content)
    parsed = inferValues(parsed)

    check parsed.variables[0].values == @["blue", "green", "red"]
    check parsed.variables[0].cardinality == 3
    check parsed.variables[1].values == @["large", "small"]
    check parsed.variables[1].cardinality == 2


suite "CSV analysis":

  test "analyze simple CSV":
    let csv = """name,age,city
Alice,25,NYC
Bob,30,LA
Carol,25,NYC
Dave,35,Chicago
"""
    let analysis = analyzeCsv(csv)

    check analysis.headers == @["name", "age", "city"]
    check analysis.columnCount == 3
    check analysis.rowCount == 4
    check analysis.cardinalities[0] == 4  # 4 unique names
    check analysis.cardinalities[1] == 3  # 3 unique ages
    check analysis.cardinalities[2] == 3  # 3 unique cities

  test "analyze CSV without header":
    let csv = """A,1,X
B,2,Y
A,1,X
C,3,Z
"""
    let analysis = analyzeCsv(csv, hasHeader = false)

    check analysis.headers.len == 0
    check analysis.columnCount == 3
    check analysis.rowCount == 4
    check analysis.cardinalities[0] == 3  # A, B, C
    check analysis.cardinalities[1] == 3  # 1, 2, 3
    check analysis.cardinalities[2] == 3  # X, Y, Z

  test "suggested abbreviations from headers":
    let csv = """Income,Education,Health
1,2,0
2,3,1
"""
    let analysis = analyzeCsv(csv)

    check analysis.suggestedAbbrevs == @["I", "E", "H"]

  test "analyze CSV with tabs":
    let csv = "A\tB\tC\n1\t2\t3\n4\t5\t6"
    let analysis = analyzeCsv(csv, delimiter = '\t')

    check analysis.headers == @["A", "B", "C"]
    check analysis.rowCount == 2


suite "JSON conversion from .in":

  test "convert simple .in to JSON":
    let content = """
:action
search

:nominal
A,2,1,A
B,3,1,B

:data
0 0 10
0 1 20
1 2 30
"""
    let parsed = parseOccamIn(content)
    let json = toJson(parsed)

    check json.contains("\"name\": \"A\"")
    check json.contains("\"abbrev\": \"A\"")
    check json.contains("\"cardinality\": 2")
    check json.contains("\"isDependent\": false")
    check json.contains("\"data\": [")
    check json.contains("[\"0\", \"0\"]")
    check json.contains("\"counts\": [10.0, 20.0, 30.0]")

  test "convert .in with DV to JSON":
    let content = """
:action
fit

:nominal
X,2,1,X
Y,2,2,Y

:data
0 0 50
1 1 50
"""
    let parsed = parseOccamIn(content)
    let json = toJson(parsed)

    check json.contains("\"isDependent\": false")
    check json.contains("\"isDependent\": true")


suite "CSV to JSON conversion":

  test "convert CSV to JSON":
    let csv = """A,B,C
0,0,0
0,1,1
1,0,1
1,1,0
"""
    let json = csvToJson(csv)

    check json.contains("\"name\": \"A\"")
    check json.contains("\"abbrev\": \"A\"")
    check json.contains("\"variables\": [")
    check json.contains("\"data\": [")
    check json.contains("[\"0\", \"0\", \"0\"]")
    check json.contains("\"counts\": [1, 1, 1, 1]")

  test "convert CSV with selected columns":
    let csv = """Name,Age,City,Score
Alice,25,NYC,90
Bob,30,LA,85
"""
    # Select only Age (1) and Score (3)
    let json = csvToJson(csv, selectedColumns = @[1, 3])

    check json.contains("\"name\": \"Age\"")
    check json.contains("\"name\": \"Score\"")
    check not json.contains("\"name\": \"Name\"")
    check not json.contains("\"name\": \"City\"")

  test "convert CSV with DV specification":
    let csv = """X,Y,Z
0,0,0
1,1,1
"""
    let json = csvToJson(csv, dvColumn = 2)

    # Z should be dependent
    check json.contains("\"isDependent\": true")
    # Count X and Y as independent
    check json.count("\"isDependent\": false") == 2

  test "convert CSV with custom abbreviations":
    let csv = """Income,Education,Health
1,2,0
"""
    let json = csvToJson(csv, customAbbrevs = @["i", "e", "h"])

    check json.contains("\"abbrev\": \"i\"")
    check json.contains("\"abbrev\": \"e\"")
    check json.contains("\"abbrev\": \"h\"")

  test "cardinality detection":
    let csv = """Gender,Status
M,Active
F,Active
M,Inactive
F,Inactive
M,Pending
"""
    let json = csvToJson(csv)

    check json.contains("\"cardinality\": 2")  # Gender: M, F
    check json.contains("\"cardinality\": 3")  # Status: Active, Inactive, Pending


suite "Round-trip conversion":

  test ".in to JSON preserves structure":
    let inContent = """
:action
search

:nominal
soft,3,1,S
hard,2,1,H
result,2,2,R

:data
1 0 0 100
2 0 1 50
3 1 0 75
1 1 1 25
"""
    let parsed = parseOccamIn(inContent)
    let json = toJson(parsed)

    # Verify key elements
    check json.contains("\"cardinality\": 3")  # soft
    check json.contains("\"cardinality\": 2")  # hard and result
    check json.contains("\"isDependent\": true")  # result is DV
    check parsed.data.len == 4
    check parsed.counts == @[100.0, 50.0, 75.0, 25.0]
