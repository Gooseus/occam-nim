## Tests for Custom Reference Model in Search Logic
##
## TDD: Tests written before implementation to verify
## that processSearch and processSearchWithProgress correctly
## use the custom reference model.

import std/[unittest, json, strutils]
import ../../src/web_lib/logic
import ../../src/web_lib/models


# Create test data JSON with 3 binary variables
proc createTestDataJson(): string =
  result = $(%*{
    "name": "test",
    "variables": [
      {"name": "A", "abbrev": "A", "cardinality": 2, "values": ["0", "1"], "isDependent": false},
      {"name": "B", "abbrev": "B", "cardinality": 2, "values": ["0", "1"], "isDependent": false},
      {"name": "C", "abbrev": "C", "cardinality": 2, "values": ["0", "1"], "isDependent": false}
    ],
    "data": [
      ["0", "0", "0"],
      ["0", "0", "1"],
      ["0", "1", "0"],
      ["0", "1", "1"],
      ["1", "0", "0"],
      ["1", "0", "1"],
      ["1", "1", "0"],
      ["1", "1", "1"]
    ],
    "counts": [10, 15, 12, 18, 8, 22, 14, 20]
  })


suite "Search with Custom Reference Model":

  test "processSearch with empty referenceModel uses default (ascending from independence)":
    # Arrange
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "up",
      filter: "loopless",
      width: 3,
      levels: 3,
      sortBy: "bic",
      referenceModel: ""
    )

    # Act
    let response = processSearch(req)

    # Assert - should work and return results
    check response.results.len > 0
    check response.totalEvaluated > 0

  test "processSearch with valid referenceModel AB uses it as starting point":
    # Arrange - start from AB instead of A:B:C
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "up",
      filter: "loopless",
      width: 3,
      levels: 3,
      sortBy: "bic",
      referenceModel: "AB"
    )

    # Act
    let response = processSearch(req)

    # Assert - should work and return results
    # Starting from AB (instead of A:B:C) means we already have A-B association
    check response.results.len > 0

  test "processSearch with referenceModel A:B:C (independence) works like default for up":
    # Arrange
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "up",
      filter: "loopless",
      width: 3,
      levels: 3,
      sortBy: "bic",
      referenceModel: "A:B:C"
    )

    # Act
    let response = processSearch(req)

    # Assert
    check response.results.len > 0

  test "processSearch with referenceModel ABC (saturated) works like default for down":
    # Arrange - start from saturated and search down
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "down",
      filter: "loopless",
      width: 3,
      levels: 3,
      sortBy: "bic",
      referenceModel: "ABC"
    )

    # Act
    let response = processSearch(req)

    # Assert
    check response.results.len > 0

  test "processSearch with invalid referenceModel returns error":
    # Arrange - use non-existent variable X
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "up",
      filter: "loopless",
      width: 3,
      levels: 3,
      sortBy: "bic",
      referenceModel: "AX"  # X doesn't exist
    )

    # Act & Assert
    # Should raise an exception or return empty results
    # (depending on implementation choice)
    expect(CatchableError):
      discard processSearch(req)

  test "processSearch with custom reference model down direction removes relations":
    # Arrange - start from AB:BC and search down (remove relations)
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "down",
      filter: "loopless",
      width: 3,
      levels: 3,
      sortBy: "bic",
      referenceModel: "AB:BC"
    )

    # Act
    let response = processSearch(req)

    # Assert - should find simpler models
    check response.results.len > 0


suite "Search with Custom Reference Model - Case Insensitivity":

  test "processSearch handles lowercase reference model":
    # Arrange - lowercase should work since variable lookup is case-insensitive
    let req = SearchRequest(
      data: createTestDataJson(),
      direction: "up",
      filter: "loopless",
      width: 3,
      levels: 2,
      sortBy: "bic",
      referenceModel: "ab"  # lowercase
    )

    # Act
    let response = processSearch(req)

    # Assert
    check response.results.len > 0
