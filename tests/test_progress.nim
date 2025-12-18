## Tests for Progress Reporting
##
## TDD tests for the progress callback infrastructure.
## These tests define the expected behavior before implementation.

import std/[unittest, times]

# Import will fail until we implement the module
import ../src/occam/core/progress

suite "Progress Types":

  test "ProgressKind enum has expected values":
    # Arrange & Act - verify enum exists with expected variants
    let started = pkSearchStarted
    let level = pkSearchLevel
    let complete = pkSearchComplete

    # Assert - enum values are distinct
    check started != level
    check level != complete
    check started != complete

  test "ProgressEvent can be constructed with search level info":
    # Arrange
    let level = 3
    let total = 7
    let evaluated = 45
    let bestName = "AB:BC"
    let bestStat = -23.5

    # Act
    let event = ProgressEvent(
      kind: pkSearchLevel,
      currentLevel: level,
      totalLevels: total,
      totalModelsEvaluated: evaluated,
      bestModelName: bestName,
      bestStatistic: bestStat,
      statisticName: "BIC"
    )

    # Assert
    check event.kind == pkSearchLevel
    check event.currentLevel == 3
    check event.totalLevels == 7
    check event.totalModelsEvaluated == 45
    check event.bestModelName == "AB:BC"
    check event.bestStatistic == -23.5
    check event.statisticName == "BIC"

  test "ProgressEvent timestamp defaults to 0":
    # Arrange & Act
    let event = ProgressEvent(kind: pkSearchStarted)

    # Assert
    check event.timestamp == 0.0

suite "Progress Config":

  test "initProgressConfig with no callback is disabled":
    # Arrange & Act
    let config = initProgressConfig()

    # Assert
    check config.callback == nil
    check config.enabled == false

  test "initProgressConfig with callback is enabled":
    # Arrange
    var callCount = 0
    let cb = proc(e: ProgressEvent) {.gcsafe.} =
      callCount += 1

    # Act
    let config = initProgressConfig(callback = cb)

    # Assert
    check config.callback != nil
    check config.enabled == true

  test "emit with nil callback does not crash":
    # Arrange
    let config = initProgressConfig()  # No callback
    let event = ProgressEvent(kind: pkSearchStarted)

    # Act & Assert - should not crash
    config.emit(event)

  test "emit with callback invokes it":
    # Arrange
    var receivedEvent: ProgressEvent
    var callCount = 0
    let cb = proc(e: ProgressEvent) {.gcsafe.} =
      {.cast(gcsafe).}:
        receivedEvent = e
        callCount += 1

    let config = initProgressConfig(callback = cb)
    let event = ProgressEvent(
      kind: pkSearchLevel,
      currentLevel: 2,
      totalLevels: 5
    )

    # Act
    config.emit(event)

    # Assert
    check callCount == 1
    check receivedEvent.kind == pkSearchLevel
    check receivedEvent.currentLevel == 2

  test "emit with disabled config does not invoke callback":
    # Arrange
    var callCount = 0
    let cb = proc(e: ProgressEvent) {.gcsafe.} =
      callCount += 1

    var config = initProgressConfig(callback = cb)
    config.enabled = false  # Explicitly disable

    let event = ProgressEvent(kind: pkSearchStarted)

    # Act
    config.emit(event)

    # Assert
    check callCount == 0

suite "Progress Event Constructors":

  test "makeSearchStartEvent creates correct event":
    # Arrange & Act
    let event = makeSearchStartEvent(totalLevels = 7, statName = "BIC")

    # Assert
    check event.kind == pkSearchStarted
    check event.totalLevels == 7
    check event.statisticName == "BIC"
    check event.timestamp > 0  # Should have current time

  test "makeLevelEvent creates correct event":
    # Arrange & Act
    let event = makeLevelEvent(
      level = 3,
      totalLevels = 7,
      modelsEvaluated = 45,
      bestName = "AB:BC:CD",
      bestStat = -15.3,
      statName = "AIC"
    )

    # Assert
    check event.kind == pkSearchLevel
    check event.currentLevel == 3
    check event.totalLevels == 7
    check event.totalModelsEvaluated == 45
    check event.bestModelName == "AB:BC:CD"
    check event.bestStatistic == -15.3
    check event.statisticName == "AIC"
    check event.timestamp > 0

  test "makeCompleteEvent creates correct event":
    # Arrange & Act
    let event = makeCompleteEvent(
      totalModels = 127,
      bestName = "AB:BC",
      bestStat = -28.7,
      statName = "BIC"
    )

    # Assert
    check event.kind == pkSearchComplete
    check event.totalModelsEvaluated == 127
    check event.bestModelName == "AB:BC"
    check event.bestStatistic == -28.7
    check event.statisticName == "BIC"
    check event.timestamp > 0

suite "Progress Callback Thread Safety":

  test "callback marked gcsafe can be stored":
    # Arrange
    let cb: ProgressCallback = proc(e: ProgressEvent) {.gcsafe.} =
      discard

    # Act
    let config = initProgressConfig(callback = cb)

    # Assert
    check config.callback != nil

  test "callback captures variables safely":
    # Arrange
    var captured = 0
    let cb = proc(e: ProgressEvent) {.gcsafe.} =
      {.cast(gcsafe).}:
        captured += 1

    let config = initProgressConfig(callback = cb)

    # Act
    config.emit(ProgressEvent(kind: pkSearchStarted))
    config.emit(ProgressEvent(kind: pkSearchLevel))
    config.emit(ProgressEvent(kind: pkSearchComplete))

    # Assert
    check captured == 3
