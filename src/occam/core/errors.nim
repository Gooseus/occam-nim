## OCCAM Error Types
##
## Hierarchical exception types for OCCAM operations.
## All OCCAM errors inherit from OccamError which inherits from CatchableError.

{.push raises: [].}

type
  OccamError* = object of CatchableError
    ## Base error type for all OCCAM errors.
    ## Use this to catch any OCCAM-specific error.

  ValidationError* = object of OccamError
    ## Raised when input validation fails.
    ## Examples: invalid variable indices, empty data, mismatched dimensions.

  ComputationError* = object of OccamError
    ## Raised when a mathematical computation fails.
    ## Examples: numerical instability, invalid intermediate results.

  ConvergenceError* = object of ComputationError
    ## Raised when an iterative algorithm fails to converge.
    ## Examples: IPF exceeds max iterations, BP message passing diverges.
    iterations*: int
    tolerance*: float64
    finalError*: float64

  ModelError* = object of OccamError
    ## Raised when model construction or validation fails.
    ## Examples: invalid relation structure, junction tree build failure.

  JunctionTreeError* = object of ModelError
    ## Raised when junction tree construction fails.
    ## Examples: non-triangulated graph, disconnected cliques.

  SearchError* = object of OccamError
    ## Raised when search operations encounter problems.
    ## Examples: invalid starting model, search space exhausted.


# Convenience constructors for error types with additional fields

proc newConvergenceError*(msg: string; iterations: int; tolerance, finalError: float64): ref ConvergenceError =
  ## Create a new ConvergenceError with iteration details.
  result = newException(ConvergenceError, msg)
  result.iterations = iterations
  result.tolerance = tolerance
  result.finalError = finalError
