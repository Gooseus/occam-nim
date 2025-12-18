## OCCAM WebAssembly/JavaScript Entry Point
##
## Minimal entry point for browser deployment.
## Can be compiled either:
##   1. Nim JS backend: nim js -d:nodejs src/occam_wasm.nim
##   2. Emscripten WASM: nim c --os:linux --cpu:wasm32 --cc:clang -d:emscripten src/occam_wasm.nim
##
## Exported functions accept JSON strings and return JSON strings.
## No file I/O - all data passed through function parameters.
## Single-threaded (WASM limitation without SharedArrayBuffer).

import std/[json, strutils]
import occam/core/types
import occam/core/variable
import occam/core/key
import occam/core/table
import occam/core/relation
import occam/core/model
import occam/math/ipf
import occam/math/entropy

when defined(js):
  # JavaScript backend
  {.emit: """
  // Mark functions for export to JS
  """.}

when defined(emscripten):
  # Emscripten WASM build
  {.emit: """
  #include <emscripten.h>
  """.}

proc parseVariableList(varDefs: JsonNode): VariableList =
  ## Parse variable definitions from JSON
  ## Format: [{"name": "A", "abbrev": "A", "cardinality": 2}, ...]
  result = initVariableList()
  for vdef in varDefs:
    let name = vdef["name"].getStr()
    let abbrev = vdef.getOrDefault("abbrev").getStr(name)
    let card = Cardinality(vdef["cardinality"].getInt())
    discard result.add(initVariable(name, abbrev, card))

proc parseTable(dataNode: JsonNode, varList: VariableList): ContingencyTable =
  ## Parse contingency table from JSON
  ## Format: [{"key": [0, 1, 0], "count": 42}, ...] or {"010": 42, ...}
  result = initContingencyTable(varList.keySize)

  if dataNode.kind == JArray:
    # Array of {key, count} objects
    for entry in dataNode:
      var pairs: seq[(VariableIndex, int)]
      var i = 0
      for idx in entry["key"]:
        pairs.add((VariableIndex(i), idx.getInt()))
        inc i
      let key = buildKey(varList, pairs)
      let count = entry["count"].getFloat()
      result.add(key, count)
  elif dataNode.kind == JObject:
    # Object with string keys "010": count
    for keyStr, countNode in dataNode:
      var pairs: seq[(VariableIndex, int)]
      for i, c in keyStr:
        pairs.add((VariableIndex(i), ord(c) - ord('0')))
      let key = buildKey(varList, pairs)
      result.add(key, countNode.getFloat())

proc parseModel(modelStr: string, varList: VariableList): Model =
  ## Parse OCCAM model string like "AB:BC:AC"
  var relations: seq[Relation]
  for relStr in modelStr.split(':'):
    var indices: seq[VariableIndex]
    for c in relStr:
      # Find variable by abbrev
      for i in 0..<varList.len:
        if varList[VariableIndex(i)].abbrev == $c:
          indices.add(VariableIndex(i))
          break
    if indices.len > 0:
      relations.add(initRelation(indices))
  result = initModel(relations)

proc buildResultJson(fitted: ContingencyTable, varList: VariableList): JsonNode =
  ## Convert fitted table to JSON result
  result = newJObject()
  var entries = newJArray()
  for tup in fitted:
    var entry = newJObject()
    var keyArr = newJArray()
    # Decode variable values from packed key
    for i in 0..<varList.len:
      let value = tup.key.getValue(varList, VariableIndex(i))
      keyArr.add(%value)
    entry["key"] = keyArr
    entry["count"] = %tup.value
    entries.add(entry)
  result["data"] = entries
  result["entropy"] = %entropy(fitted)

proc fitModelJson*(inputJson: cstring): cstring {.exportc, cdecl.} =
  ## Fit a model to data
  ##
  ## Input JSON format:
  ## {
  ##   "variables": [{"name": "A", "abbrev": "A", "cardinality": 2}, ...],
  ##   "data": [{"key": [0, 1], "count": 42}, ...],
  ##   "model": "AB:BC"
  ## }
  ##
  ## Returns JSON with fitted distribution and statistics.
  try:
    let input = parseJson($inputJson)
    let varList = parseVariableList(input["variables"])
    let table = parseTable(input["data"], varList)
    let model = parseModel(input["model"].getStr(), varList)

    # Fit using IPF
    let ipfResult = ipf(table, model.relations, varList)

    let resultNode = buildResultJson(ipfResult.fitTable, varList)
    resultNode["iterations"] = %ipfResult.iterations
    resultNode["converged"] = %ipfResult.converged
    resultNode["model"] = %model.printName(varList)
    resultNode["success"] = %true

    return cstring($resultNode)
  except CatchableError as e:
    let errResult = %*{"success": false, "error": e.msg}
    return cstring($errResult)

proc computeEntropyJson*(inputJson: cstring): cstring {.exportc, cdecl.} =
  ## Compute entropy of a distribution
  ##
  ## Input JSON format:
  ## {
  ##   "variables": [{"name": "A", "cardinality": 2}, ...],
  ##   "data": [{"key": [0, 1], "count": 42}, ...]
  ## }
  ##
  ## Returns JSON with entropy value.
  try:
    let input = parseJson($inputJson)
    let varList = parseVariableList(input["variables"])
    let table = parseTable(input["data"], varList)

    let h = entropy(table)
    let resultNode = %*{"entropy": h, "success": true}

    return cstring($resultNode)
  except CatchableError as e:
    let errResult = %*{"success": false, "error": e.msg}
    return cstring($errResult)

when isMainModule:
  # Test harness for development
  let testInput = """{
    "variables": [
      {"name": "A", "abbrev": "A", "cardinality": 2},
      {"name": "B", "abbrev": "B", "cardinality": 2}
    ],
    "data": [
      {"key": [0, 0], "count": 10},
      {"key": [0, 1], "count": 20},
      {"key": [1, 0], "count": 30},
      {"key": [1, 1], "count": 40}
    ],
    "model": "A:B"
  }"""

  let result = fitModelJson(cstring(testInput))
  echo "Result: ", result

  let entropyInput = """{
    "variables": [
      {"name": "A", "cardinality": 2}
    ],
    "data": [
      {"key": [0], "count": 50},
      {"key": [1], "count": 50}
    ]
  }"""

  let entropyResult = computeEntropyJson(cstring(entropyInput))
  echo "Entropy: ", entropyResult
