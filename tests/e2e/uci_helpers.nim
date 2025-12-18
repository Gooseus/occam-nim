## UCI Dataset helpers for e2e tests
## Downloads and converts UCI Machine Learning Repository datasets on demand

import std/[os, httpclient, strutils, sequtils, tables]
import ../../src/occam/io/formats
import ../../src/occam/io/parser

const
  BaseUrl = "https://archive.ics.uci.edu/ml/machine-learning-databases/"
  FixturesDir* = currentSourcePath.parentDir.parentDir / "fixtures" / "uci"

type
  DatasetConfig = object
    url: string
    headers: seq[string]
    dvColumn: int  # -1 for neutral, or column index
    hasHeader: bool
    delimiter: char
    abbrevs: seq[string]
    skipFirstColumn: bool  # For datasets like Zoo with name column

const Datasets* = {
  "car": DatasetConfig(
    url: BaseUrl & "car/car.data",
    headers: @["buying", "maint", "doors", "persons", "lug_boot", "safety", "class"],
    dvColumn: 6,
    hasHeader: false,
    delimiter: ',',
    abbrevs: @["B", "M", "D", "P", "L", "S", "C"],
    skipFirstColumn: false
  ),
  "tictactoe": DatasetConfig(
    url: BaseUrl & "tic-tac-toe/tic-tac-toe.data",
    headers: @["tl", "tm", "tr", "ml", "mm", "mr", "bl", "bm", "br", "class"],
    dvColumn: 9,
    hasHeader: false,
    delimiter: ',',
    abbrevs: @["A", "B", "C", "D", "E", "F", "G", "H", "I", "Z"],
    skipFirstColumn: false
  ),
  "zoo": DatasetConfig(
    url: BaseUrl & "zoo/zoo.data",
    headers: @["name", "hair", "feathers", "eggs", "milk", "airborne", "aquatic",
               "predator", "toothed", "backbone", "breathes", "venomous", "fins",
               "legs", "tail", "domestic", "catsize", "type"],
    dvColumn: 17,  # 'type' is column 17 (0-indexed), but we skip 'name' so it becomes 16
    hasHeader: false,
    delimiter: ',',
    abbrevs: @["H", "F", "E", "M", "A", "Q", "P", "T", "B", "R", "V", "I", "L", "X", "D", "C", "Z"],
    skipFirstColumn: true  # Skip 'name' column
  ),
  "mushroom": DatasetConfig(
    url: BaseUrl & "mushroom/agaricus-lepirata.data",
    headers: @["class", "cap-shape", "cap-surface", "cap-color", "bruises", "odor",
               "gill-attachment", "gill-spacing", "gill-size", "gill-color",
               "stalk-shape", "stalk-root", "stalk-surface-above-ring",
               "stalk-surface-below-ring", "stalk-color-above-ring",
               "stalk-color-below-ring", "veil-type", "veil-color",
               "ring-number", "ring-type", "spore-print-color",
               "population", "habitat"],
    dvColumn: 0,  # 'class' is first column (edible/poisonous)
    hasHeader: false,
    delimiter: ',',
    abbrevs: @["Z", "A", "B", "C", "D", "E", "F", "G", "H", "I", "J", "K",
               "L", "M", "N", "O", "P", "Q", "R", "S", "T", "U", "V"],
    skipFirstColumn: false
  ),
  "nursery": DatasetConfig(
    url: BaseUrl & "nursery/nursery.data",
    headers: @["parents", "has_nurs", "form", "children", "housing",
               "finance", "social", "health", "class"],
    dvColumn: 8,  # 'class' is last column
    hasHeader: false,
    delimiter: ',',
    abbrevs: @["P", "N", "F", "C", "H", "I", "S", "L", "Z"],
    skipFirstColumn: false
  )
}.toTable


proc downloadDataset*(name: string): string =
  ## Download dataset from UCI and return content
  if name notin Datasets:
    raise newException(ValueError, "Unknown dataset: " & name)

  let config = Datasets[name]
  echo "Downloading ", name, " from ", config.url, "..."

  var client = newHttpClient()
  defer: client.close()

  try:
    result = client.getContent(config.url)
    echo "Downloaded ", result.len, " bytes"
  except HttpRequestError as e:
    # Try alternate URL for mushroom (typo in original)
    if name == "mushroom":
      let altUrl = BaseUrl & "mushroom/agaricus-lepiota.data"
      echo "Trying alternate URL: ", altUrl
      result = client.getContent(altUrl)
      echo "Downloaded ", result.len, " bytes"
    else:
      raise e


proc convertToJson*(name: string; csvContent: string): string =
  ## Convert downloaded CSV to OCCAM JSON format
  if name notin Datasets:
    raise newException(ValueError, "Unknown dataset: " & name)

  let config = Datasets[name]

  # Prepend headers since UCI datasets don't have them
  var contentWithHeaders = config.headers.join(",") & "\n" & csvContent

  # Determine which columns to include
  var selectedColumns: seq[int]
  var dvCol = config.dvColumn

  if config.skipFirstColumn:
    # Skip first column (e.g., animal name in Zoo)
    for i in 1..<config.headers.len:
      selectedColumns.add(i)
    # Adjust DV column index since we're skipping column 0
    if dvCol > 0:
      dvCol = dvCol - 1
  else:
    # Include all columns
    for i in 0..<config.headers.len:
      selectedColumns.add(i)

  # Use abbreviated names for variables
  var abbrevs: seq[string]
  if config.skipFirstColumn:
    abbrevs = config.abbrevs
  else:
    abbrevs = config.abbrevs

  result = csvToJson(
    contentWithHeaders,
    selectedColumns = selectedColumns,
    dvColumn = config.dvColumn,  # Use original dvColumn since csvToJson handles selectedColumns
    hasHeader = true,
    delimiter = config.delimiter,
    customAbbrevs = abbrevs
  )


proc ensureDataset*(name: string): string =
  ## Ensure dataset JSON exists, downloading or converting if needed. Returns path.
  if name notin Datasets:
    raise newException(ValueError, "Unknown dataset: " & name)

  # Create fixtures directory if needed
  if not dirExists(FixturesDir):
    createDir(FixturesDir)

  let jsonPath = FixturesDir / name & ".json"
  let csvPath = FixturesDir / name & ".csv"

  if not fileExists(jsonPath):
    # Try to convert from CSV if it exists
    if fileExists(csvPath):
      echo "Converting ", csvPath, " to JSON..."
      let csvContent = readFile(csvPath)
      let jsonContent = convertToJson(name, csvContent)
      writeFile(jsonPath, jsonContent)
      echo "Saved to ", jsonPath
    else:
      # Try to download (requires -d:ssl compilation)
      echo "Dataset ", name, " not found, downloading..."
      try:
        let csvContent = downloadDataset(name)
        let jsonContent = convertToJson(name, csvContent)
        writeFile(jsonPath, jsonContent)
        echo "Saved to ", jsonPath
      except HttpRequestError as e:
        if "SSL" in e.msg:
          let config = Datasets[name]
          raise newException(IOError,
            "SSL not available. Download manually with:\n" &
            "  curl -L -o " & csvPath & " \"" & config.url & "\"\n" &
            "Then re-run the tests.")
        else:
          raise e

  result = jsonPath


proc loadUciDataset*(name: string): DataSpec =
  ## Load UCI dataset, downloading if needed
  let path = ensureDataset(name)
  result = loadDataSpec(path)


proc getDatasetInfo*(name: string): tuple[instances: int, features: int, dvColumn: int] =
  ## Get expected dataset dimensions
  case name
  of "car":
    result = (1728, 7, 6)
  of "tictactoe":
    result = (958, 10, 9)
  of "zoo":
    result = (101, 17, 16)  # 17 features after dropping name
  of "mushroom":
    result = (8124, 23, 0)
  of "nursery":
    result = (12960, 9, 8)
  else:
    raise newException(ValueError, "Unknown dataset: " & name)
