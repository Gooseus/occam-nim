## OCCAM CLI - Command line interface for Reconstructability Analysis
##
## This is the main entry point for the CLI. Commands are organized into
## separate modules for maintainability:
##
## - cli_lib/formatting.nim: Output formatting utilities
## - cli_lib/cmd_search.nim: Model space search command
## - cli_lib/cmd_fit.nim: Single model fitting and analysis
## - cli_lib/cmd_convert.nim: Data conversion and preprocessing
## - cli_lib/cmd_generate.nim: Synthetic data generation and utilities

import cligen
import cli_lib/cmd_search
import cli_lib/cmd_fit
import cli_lib/cmd_convert
import cli_lib/cmd_generate
import cli_lib/cmd_preprocess


when isMainModule:
  dispatchMulti(
    [search, help = {"input": "JSON data file",
                     "direction": "Search direction: up or down",
                     "filter": "Search filter: loopless, full, disjoint, chain",
                     "width": "Models to keep at each level",
                     "levels": "Maximum search levels",
                     "sort": "Statistic to sort by: ddf, aic, bic",
                     "parallel": "Use parallel search (default: true)",
                     "verbose": "Show detailed output"}],
    [info],
    [fit, help = {"input": "JSON data file",
                  "model": "Model specification (e.g., AB:BC or AB:BC:AC)",
                  "compare": "Model to compare for incremental alpha (e.g., AB:C)",
                  "residuals": "Show residuals table",
                  "conditionalDv": "Show P(DV|IVs) table (directed systems)",
                  "confusionMatrix": "Show confusion matrix (directed systems)",
                  "verbose": "Show detailed output"}],
    [tableCmd, cmdName = "table",
               help = {"input": "JSON data file",
                       "model": "Model specification (e.g., AB:BC or AB:BC:AC)",
                       "verbose": "Show legend and detailed output"}],
    [generate, help = {"variables": "Variable spec: name:card,... (e.g., A:2,B:2,C:2)",
                       "model": "Model structure (e.g., AB:BC for chain, AB:BC:AC for triangle)",
                       "samples": "Number of samples to generate",
                       "strength": "Dependency strength (0.5=independent, 1.0=deterministic)",
                       "seed": "Random seed (-1 for random)",
                       "output": "Output JSON file (stdout if empty)"}],
    [convert, help = {"input": "OCCAM .in file path",
                      "output": "Output JSON file (stdout if empty)",
                      "inferVals": "Infer value labels from data"}],
    [latticeCmd, cmdName = "lattice",
                 help = {"input": "JSON data file (optional)",
                         "variables": "Variable spec: name:card,name:card,... (e.g., A:2,B:2,C:2)",
                         "loopless": "Only show loopless models",
                         "maxModels": "Max models to enumerate",
                         "showLoops": "Show which models have loops"}],
    [analyzeCsvCmd, cmdName = "analyze-csv",
                 help = {"input": "CSV file path",
                         "hasHeader": "CSV has header row",
                         "delimiter": "Column delimiter",
                         "interactive": "Interactive configuration mode"}],
    [csvToJsonCmd, cmdName = "csv-to-json",
                   help = {"input": "CSV file path",
                           "output": "Output JSON file (stdout if empty)",
                           "columns": "Column indices to include (comma-separated)",
                           "dv": "Dependent variable column (-1 for none)",
                           "hasHeader": "CSV has header row",
                           "delimiter": "Column delimiter",
                           "abbrevs": "Custom abbreviations (comma-separated)",
                           "names": "Custom variable names (comma-separated)"}],
    [binCmd, cmdName = "bin",
             help = {"input": "JSON or CSV data file",
                     "output": "Output JSON file (stdout if empty)",
                     "varSpecs": "Variable binning spec: NAME:STRATEGY:PARAM (repeatable)",
                     "auto": "Auto-detect and bin high-cardinality columns",
                     "targetCard": "Target cardinality for auto-binning (default: 5)",
                     "threshold": "Only auto-bin columns with > threshold unique values",
                     "config": "JSON config file for binning specifications",
                     "verbose": "Show detailed output"}],
    [sequenceCmd, cmdName = "sequence",
                  help = {"kind": "Sequence type: primes, naturals, odds",
                          "limit": "Upper bound for sequence generation",
                          "count": "Generate this many numbers (overrides limit)",
                          "start": "Start value (only include values >= start)",
                          "columns": "Column specs: R3,R5,R7,collatz,digits,factors",
                          "target": "Target column for DV (e.g., R3)",
                          "output": "Output file (stdout if empty)",
                          "format": "Output format: json, csv",
                          "includeValues": "Include actual number values",
                          "consecutive": "Use consecutive pairs (prev→next)",
                          "verbose": "Show detailed output"}],
    [samplesizeCmd, cmdName = "samplesize",
                    help = {"samples": "Number of observations (if known)",
                            "kind": "Sequence type: primes, naturals",
                            "limit": "Upper bound for sequence (to estimate N)",
                            "start": "Start value for range",
                            "targetObsPerCell": "Minimum obs/cell for adequacy (default: 10)",
                            "required": "Show required sample sizes for each # of IVs",
                            "maxVars": "Max variables to show in table (default: 10)"}],
    [preprocess, help = {"input": "Input file (JSON, CSV, or OCCAM .in format)",
                         "output": "Output JSON file (stdout if empty)",
                         "format": "Input format: auto, json, csv, occam",
                         "columns": "Columns to include (e.g., \"0,2-4,Age\" or \"*\" for all)",
                         "autoBin": "Auto-bin high-cardinality columns",
                         "targetCard": "Target cardinality for auto-binning (default: 5)",
                         "binThreshold": "Only bin columns with cardinality > threshold (default: 10)",
                         "hasHeader": "CSV has header row",
                         "delimiter": "CSV column delimiter",
                         "dv": "Dependent variable column index for CSV",
                         "name": "Dataset name (defaults to filename)",
                         "verbose": "Show detailed output"}]
  )
