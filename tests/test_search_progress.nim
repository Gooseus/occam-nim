## Tests for Search Progress Integration
##
## TDD tests verifying that parallelSearch emits progress events
## at the expected points during search.

import std/[unittest]
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/key
import ../src/occam/core/table
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/core/progress
import ../src/occam/search/parallel

# Test helper to create a simple dataset
proc createTestData(): (VariableList, ContingencyTable) =
  # 3 binary variables: A, B, C
  var varList = initVariableList()
  discard varList.add(initVariable("A", "A", Cardinality(2)))
  discard varList.add(initVariable("B", "B", Cardinality(2)))
  discard varList.add(initVariable("C", "C", Cardinality(2)))

  var table = initTable(varList.keySize)
  # Add some test data
  for a in 0..1:
    for b in 0..1:
      for c in 0..1:
        let key = varList.buildKey(@[
          (VariableIndex(0), a),
          (VariableIndex(1), b),
          (VariableIndex(2), c)
        ])
        table.add(key, float64(10 + a * 5 + b * 3 + c * 2))

  table.sort()
  table.normalize()
  (varList, table)

suite "Search Progress Integration":

  test "parallelSearch with no progress config works":
    # Arrange
    let (varList, table) = createTestData()
    # Independence model: A:B:C (each variable alone)
    let startModel = initModel(@[
      initRelation(@[VariableIndex(0)]),  # A
      initRelation(@[VariableIndex(1)]),  # B
      initRelation(@[VariableIndex(2)])   # C
    ])

    # Act - default progress config (disabled)
    let results = parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchBIC,
      width = 3, maxLevels = 3,
      useParallel = false
    )

    # Assert - should return results without crashing
    check results.len > 0

  test "parallelSearch emits pkSearchStarted event":
    # Arrange
    let (varList, table) = createTestData()
    let startModel = initModel(@[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)]),
      initRelation(@[VariableIndex(2)])
    ])

    var receivedStart = false
    var startLevels = 0
    var startStatName = ""

    let config = initProgressConfig(
      callback = proc(e: ProgressEvent) {.gcsafe.} =
        {.cast(gcsafe).}:
          if e.kind == pkSearchStarted:
            receivedStart = true
            startLevels = e.totalLevels
            startStatName = e.statisticName
    )

    # Act
    discard parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchBIC,
      width = 3, maxLevels = 5,
      useParallel = false,
      progress = config
    )

    # Assert
    check receivedStart == true
    check startLevels == 5
    check startStatName == "BIC"

  test "parallelSearch emits pkSearchLevel events for each level":
    # Arrange
    let (varList, table) = createTestData()
    let startModel = initModel(@[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)]),
      initRelation(@[VariableIndex(2)])
    ])

    var levelEvents: seq[ProgressEvent] = @[]

    let config = initProgressConfig(
      callback = proc(e: ProgressEvent) {.gcsafe.} =
        {.cast(gcsafe).}:
          if e.kind == pkSearchLevel:
            levelEvents.add(e)
    )

    # Act
    discard parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchBIC,
      width = 3, maxLevels = 3,
      useParallel = false,
      progress = config
    )

    # Assert - should have level events (may be fewer than maxLevels if search terminates early)
    check levelEvents.len >= 1
    # First level should be level 1
    check levelEvents[0].currentLevel == 1
    # All levels should have totalLevels = 3
    for e in levelEvents:
      check e.totalLevels == 3

  test "parallelSearch emits pkSearchComplete event":
    # Arrange
    let (varList, table) = createTestData()
    let startModel = initModel(@[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)]),
      initRelation(@[VariableIndex(2)])
    ])

    var receivedComplete = false
    var completeTotalModels = 0
    var completeBestName = ""

    let config = initProgressConfig(
      callback = proc(e: ProgressEvent) {.gcsafe.} =
        {.cast(gcsafe).}:
          if e.kind == pkSearchComplete:
            receivedComplete = true
            completeTotalModels = e.totalModelsEvaluated
            completeBestName = e.bestModelName
    )

    # Act
    discard parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchBIC,
      width = 3, maxLevels = 3,
      useParallel = false,
      progress = config
    )

    # Assert
    check receivedComplete == true
    check completeTotalModels >= 1
    check completeBestName.len > 0

  test "parallelSearch level events track model count":
    # Arrange
    let (varList, table) = createTestData()
    let startModel = initModel(@[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)]),
      initRelation(@[VariableIndex(2)])
    ])

    var lastModelsEvaluated = 0

    let config = initProgressConfig(
      callback = proc(e: ProgressEvent) {.gcsafe.} =
        {.cast(gcsafe).}:
          if e.kind == pkSearchLevel:
            # Each level should have more or equal models evaluated
            lastModelsEvaluated = e.totalModelsEvaluated
    )

    # Act
    discard parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchBIC,
      width = 3, maxLevels = 3,
      useParallel = false,
      progress = config
    )

    # Assert - should have evaluated some models
    check lastModelsEvaluated > 0

  test "parallelSearch events have correct statistics name":
    # Arrange
    let (varList, table) = createTestData()
    let startModel = initModel(@[
      initRelation(@[VariableIndex(0)]),
      initRelation(@[VariableIndex(1)]),
      initRelation(@[VariableIndex(2)])
    ])

    var aicStatName = ""
    var ddfStatName = ""

    # Test with AIC
    let aicConfig = initProgressConfig(
      callback = proc(e: ProgressEvent) {.gcsafe.} =
        {.cast(gcsafe).}:
          if e.kind == pkSearchStarted:
            aicStatName = e.statisticName
    )

    discard parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchAIC,
      width = 2, maxLevels = 2,
      useParallel = false,
      progress = aicConfig
    )

    # Test with DDF
    let ddfConfig = initProgressConfig(
      callback = proc(e: ProgressEvent) {.gcsafe.} =
        {.cast(gcsafe).}:
          if e.kind == pkSearchStarted:
            ddfStatName = e.statisticName
    )

    discard parallelSearch(
      varList, table, startModel,
      SearchLoopless, SearchDDF,
      width = 2, maxLevels = 2,
      useParallel = false,
      progress = ddfConfig
    )

    # Assert
    check aicStatName == "AIC"
    check ddfStatName == "DDF"
