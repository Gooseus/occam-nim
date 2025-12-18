## OCCAM - Reconstructability Analysis Toolkit
##
## A Nim library for Reconstructability Analysis (RA), a methodology for
## discrete multivariate modeling based on information theory and graph theory.
##
## ## Quick Start
##
## ```nim
## import occam
##
## # Load data from JSON file
## let data = loadDataSpec("mydata.json")
## let varList = data.toVariableList()
## let table = data.toTable(varList)
##
## # Create a manager and fit a model
## var mgr = initVBManager(varList, table)
## let model = mgr.makeModel("AB:BC:C")  # A model with three relations
## let result = mgr.fitModel(model)
##
## echo "Entropy: ", result.h
## echo "AIC: ", result.aic
## echo "BIC: ", result.bic
## ```
##
## ## Module Organization
##
## - `occam/core/*` - Core types: Variable, Table, Relation, Model
## - `occam/math/*` - Entropy, statistics, IPF, belief propagation
## - `occam/manager/*` - VBManager coordinates fitting and analysis
## - `occam/search/*` - Model search algorithms
## - `occam/io/*` - Data loading and format conversion
##
## ## Selective Imports
##
## For finer control, import specific modules:
## ```nim
## import occam/core/[types, variable, table]
## import occam/manager/vb
## import occam/math/[entropy, statistics]
## ```
##
## ## Advanced Usage
##
## For direct access to graph algorithms, IPF, or belief propagation:
## ```nim
## import occam/core/[graph, junction_tree]
## import occam/math/[ipf, belief_propagation]
## ```

# Core types and data structures
import occam/core/types
import occam/core/variable
import occam/core/key
import occam/core/table
import occam/core/relation
import occam/core/model
import occam/core/results
import occam/core/errors

# Mathematical operations
import occam/math/entropy
import occam/math/statistics
import occam/math/chow_liu
import occam/math/forward_backward

# Manager
import occam/manager/vb

# IO
import occam/io/parser

# Search
import occam/search/base
import occam/search/loopless
import occam/search/full
import occam/search/chain
import occam/search/lattice
import occam/search/parallel

# Export all public symbols
export types
export variable
export key
export table
export relation
export model
export results
export errors
export entropy
export statistics
export chow_liu
export forward_backward
export vb
export parser
export base
export loopless
export full
export chain
export lattice
export parallel
