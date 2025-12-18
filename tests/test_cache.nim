## Test suite for cache module
## Tests RelationCache and ModelCache types for caching relations and models

import std/options
import unittest
import ../src/occam/core/types
import ../src/occam/core/variable
import ../src/occam/core/relation
import ../src/occam/core/model
import ../src/occam/manager/cache


suite "Cache key generation":
  test "cacheKey from empty seq":
    let key = cacheKey(@[])
    check key == ""

  test "cacheKey from single index":
    let key = cacheKey(@[VariableIndex(0)])
    check key == "0"

  test "cacheKey from multiple indices":
    let key = cacheKey(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check key == "0,1,2"

  test "cacheKey sorts indices":
    let key1 = cacheKey(@[VariableIndex(2), VariableIndex(0), VariableIndex(1)])
    let key2 = cacheKey(@[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    check key1 == key2
    check key1 == "0,1,2"

  test "cacheKey handles large indices":
    let key = cacheKey(@[VariableIndex(100), VariableIndex(50)])
    check key == "50,100"


suite "Relation cache initialization":
  test "initRelationCache creates empty cache":
    let rc = initRelationCache()
    check rc.len == 0

  test "empty cache contains nothing":
    let rc = initRelationCache()
    check not rc.contains(@[VariableIndex(0)])
    check not rc.contains(@[VariableIndex(0), VariableIndex(1)])


suite "Relation cache get":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "get on empty cache returns none":
    let rc = initRelationCache()
    let result = rc.get(@[VariableIndex(0)])
    check result.isNone

  test "get with nonexistent key returns none":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0)])
    discard rc.put(r)
    let result = rc.get(@[VariableIndex(1)])
    check result.isNone


suite "Relation cache put":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "put stores relation and returns it":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let stored = rc.put(r)
    check stored == r
    check rc.len == 1

  test "put returns existing on duplicate":
    var rc = initRelationCache()
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    discard rc.put(r1)
    let stored = rc.put(r2)
    check stored == r1
    check rc.len == 1  # No duplicate added

  test "put handles different variable orders":
    var rc = initRelationCache()
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let r2 = newRelation(varList, @[VariableIndex(1), VariableIndex(0)])  # Same vars, different order
    discard rc.put(r1)
    let stored = rc.put(r2)
    check stored == r1  # Returns existing (canonical)
    check rc.len == 1

  test "put stores multiple distinct relations":
    var rc = initRelationCache()
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let r3 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    discard rc.put(r1)
    discard rc.put(r2)
    discard rc.put(r3)
    check rc.len == 3


suite "Relation cache get after put":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(4)))

  test "get retrieves stored relation":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    discard rc.put(r)
    let result = rc.get(@[VariableIndex(0), VariableIndex(1)])
    check result.isSome
    check result.get() == r

  test "get retrieves with different variable order":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    discard rc.put(r)
    # Query with different order
    let result = rc.get(@[VariableIndex(1), VariableIndex(0)])
    check result.isSome
    check result.get() == r


suite "Relation cache contains":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "contains returns true for stored relation":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0)])
    discard rc.put(r)
    check rc.contains(@[VariableIndex(0)])

  test "contains returns false for unstored relation":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0)])
    discard rc.put(r)
    check not rc.contains(@[VariableIndex(1)])

  test "contains is order-independent":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    discard rc.put(r)
    check rc.contains(@[VariableIndex(1), VariableIndex(0)])


suite "Relation cache clear":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(3)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "clear removes all entries":
    var rc = initRelationCache()
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    discard rc.put(r1)
    discard rc.put(r2)
    check rc.len == 2
    rc.clear()
    check rc.len == 0

  test "clear allows re-adding":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0)])
    discard rc.put(r)
    rc.clear()
    check not rc.contains(@[VariableIndex(0)])
    discard rc.put(r)
    check rc.contains(@[VariableIndex(0)])


suite "Model cache initialization":
  test "initModelCache creates empty cache":
    let mc = initModelCache()
    check mc.len == 0

  test "empty cache contains nothing":
    let mc = initModelCache()
    check not mc.contains("AB:BC")


suite "Model cache get":
  test "get on empty cache returns none":
    let mc = initModelCache()
    let result = mc.get("AB:BC")
    check result.isNone

  test "get with nonexistent key returns none":
    var mc = initModelCache()
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    discard mc.put(m, varList)
    let result = mc.get("XYZ")
    check result.isNone


suite "Model cache put":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "put stores model and returns it":
    var mc = initModelCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    let stored = mc.put(m, varList)
    check stored == m
    check mc.len == 1

  test "put returns existing on duplicate":
    var mc = initModelCache()
    let r1 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m1 = initModel(@[r1])
    let r2 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m2 = initModel(@[r2])
    discard mc.put(m1, varList)
    let stored = mc.put(m2, varList)
    check stored == m1
    check mc.len == 1

  test "put stores multiple distinct models":
    var mc = initModelCache()
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let r3 = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m1 = initModel(@[r1])
    let m2 = initModel(@[r2])
    let m3 = initModel(@[r3])
    discard mc.put(m1, varList)
    discard mc.put(m2, varList)
    discard mc.put(m3, varList)
    check mc.len == 3


suite "Model cache get after put":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "get retrieves stored model":
    var mc = initModelCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    discard mc.put(m, varList)
    let name = m.printName(varList)
    let result = mc.get(name)
    check result.isSome
    check result.get() == m


suite "Model cache contains":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "contains returns true for stored model":
    var mc = initModelCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1)])
    let m = initModel(@[r])
    discard mc.put(m, varList)
    check mc.contains(m.printName(varList))

  test "contains returns false for unstored model":
    var mc = initModelCache()
    check not mc.contains("AB")


suite "Model cache clear":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))

  test "clear removes all entries":
    var mc = initModelCache()
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let m1 = initModel(@[r1])
    let m2 = initModel(@[r2])
    discard mc.put(m1, varList)
    discard mc.put(m2, varList)
    check mc.len == 2
    mc.clear()
    check mc.len == 0


suite "Cache edge cases":
  setup:
    var varList = initVariableList()
    discard varList.add(newVariable("A", "A", Cardinality(2)))
    discard varList.add(newVariable("B", "B", Cardinality(2)))
    discard varList.add(newVariable("C", "C", Cardinality(2)))

  test "relation cache handles empty relation":
    var rc = initRelationCache()
    let r = newRelation(varList, @[])
    discard rc.put(r)
    check rc.len == 1
    let result = rc.get(@[])
    check result.isSome
    check result.get().variableCount == 0

  test "model cache handles independence model":
    var mc = initModelCache()
    let r1 = newRelation(varList, @[VariableIndex(0)])
    let r2 = newRelation(varList, @[VariableIndex(1)])
    let m = initModel(@[r1, r2])
    discard mc.put(m, varList)
    let name = m.printName(varList)
    let result = mc.get(name)
    check result.isSome
    check result.get().relationCount == 2

  test "model cache handles saturated model":
    var mc = initModelCache()
    let r = newRelation(varList, @[VariableIndex(0), VariableIndex(1), VariableIndex(2)])
    let m = initModel(@[r])
    discard mc.put(m, varList)
    let name = m.printName(varList)
    let result = mc.get(name)
    check result.isSome
    check result.get().relationCount == 1

  test "multiple puts of same relation are idempotent":
    var rc = initRelationCache()
    let r = newRelation(varList, @[VariableIndex(0)])
    for i in 0..<10:
      discard rc.put(r)
    check rc.len == 1

  test "multiple puts of same model are idempotent":
    var mc = initModelCache()
    let r = newRelation(varList, @[VariableIndex(0)])
    let m = initModel(@[r])
    for i in 0..<10:
      discard mc.put(m, varList)
    check mc.len == 1
