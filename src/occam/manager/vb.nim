## Variable-Based Manager for OCCAM
## Coordinates projections, caching, and statistics computation

{.push raises: [].}

import std/[strutils, options]
import ../core/types
import ../core/variable
import ../core/key
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../core/junction_tree
import ../core/results
import ../core/errors
import ../core/profile
import ../math/entropy
import ../math/statistics as mathstats
import ../math/ipf
import ../math/belief_propagation as bp
import cache
import statistics as mgrstats
import fitting as mgrfitting

type
  VBManager* = object
    ## Variable-Based Manager - coordinates analysis
    varList*: VariableList
    inputData*: coretable.ContingencyTable
    normalizedData: coretable.ContingencyTable
    sampleSize*: float64
    relCache: RelationCache
    modelCache: ModelCache
    topRef: Model
    bottomRef: Model
    searchDirection*: Direction
    profiler*: ProfileAccumulator  ## Optional profiler for performance tracking


# ============ VBManager ============

proc createTopRefModel(varList: VariableList): Model =
  ## Create the saturated (top) reference model
  createSaturatedModel(varList)


proc createBottomRefModel(varList: VariableList): Model =
  ## Create the independence (bottom) reference model
  if varList.isDirected:
    # Directed system: IV relation : DV relation
    var ivIndices: seq[VariableIndex]
    var dvIndices: seq[VariableIndex]
    for vi, v in varList.pairs:
      if v.isDependent:
        dvIndices.add(vi)
      else:
        ivIndices.add(vi)

    var rels: seq[Relation]
    if ivIndices.len > 0:
      rels.add(initRelation(ivIndices))
    if dvIndices.len > 0:
      rels.add(initRelation(dvIndices))
    initModel(rels)
  else:
    # Neutral system: single-variable relations A:B:C:...
    createIndependenceModel(varList)


proc initVBManager*(varList: VariableList; inputData: coretable.ContingencyTable;
                    validate = true;
                    profileConfig = initProfileConfig(pgNone)): VBManager {.raises: [ValidationError].} =
  ## Create a new VB Manager with variable list and input data
  ##
  ## If validate is true (default), raises ValidationError on invalid inputs:
  ##   - Empty variable list
  ##   - Empty input data
  ##   - Zero sample size
  ##
  ## If profileConfig has granularity != pgNone, profiling is enabled and
  ## the manager will track timing for various operations.

  if validate:
    if varList.len == 0:
      raise newException(ValidationError, "Variable list cannot be empty")
    if inputData.len == 0:
      raise newException(ValidationError, "Input data cannot be empty")
    let sampleSum = inputData.sum
    if sampleSum <= 0.0:
      raise newException(ValidationError, "Input data sample size must be positive")

  result.varList = varList
  result.inputData = inputData
  result.sampleSize = inputData.sum
  result.relCache = initRelationCache()
  result.modelCache = initModelCache()
  result.searchDirection = Direction.Ascending

  # Initialize profiler if profiling enabled
  if profileConfig.granularity != pgNone:
    result.profiler = initProfileAccumulator(profileConfig)
  else:
    result.profiler = nil

  # Create normalized copy of data
  result.normalizedData = inputData
  result.normalizedData.normalize()

  # Create reference models
  result.topRef = createTopRefModel(varList)
  result.bottomRef = createBottomRefModel(varList)

# Alias with simpler name
proc initManager*(varList: VariableList; inputData: coretable.ContingencyTable;
                  validate = true;
                  profileConfig = initProfileConfig(pgNone)): VBManager {.raises: [ValidationError].} =
  ## Alias for `initVBManager` with a simpler name.
  initVBManager(varList, inputData, validate, profileConfig)

# Deprecated alias
proc newVBManager*(varList: VariableList; inputData: coretable.ContingencyTable;
                   validate = true): VBManager {.deprecated: "Use initVBManager instead", raises: [ValidationError].} =
  initVBManager(varList, inputData, validate)


proc topRefModel*(mgr: VBManager): Model =
  ## Get the top (saturated) reference model
  mgr.topRef


proc getNormalizedData*(mgr: VBManager): coretable.ContingencyTable =
  ## Get the normalized (probability) data table
  mgr.normalizedData


proc bottomRefModel*(mgr: VBManager): Model =
  ## Get the bottom (independence) reference model
  mgr.bottomRef


proc setSearchDirection*(mgr: var VBManager; dir: Direction) =
  ## Set the search direction
  mgr.searchDirection = dir


# ============ Relation Management ============

proc getRelation*(mgr: var VBManager; varIndices: seq[VariableIndex]): Relation =
  ## Get or create a relation for the given variables (cached)
  let cached = mgr.relCache.get(varIndices)
  if cached.isSome:
    cached.get()
  else:
    var newRel = initRelation(varIndices)
    mgr.relCache.put(newRel)


proc makeProjection*(mgr: var VBManager; rel: var Relation) =
  ## Create the projection table for a relation
  if rel.hasProjection:
    return

  let proj = mgr.inputData.project(mgr.varList, rel.varIndices)
  rel.setProjection(proj)

  # Update in cache
  discard mgr.relCache.put(rel)


# ============ Model Management ============

proc makeModel*(mgr: var VBManager; name: string): Model =
  ## Create a model from a colon-separated string like "AB:BC" or "A:B:C"
  ##
  ## Each part represents a relation using variable abbreviations.
  ## Supports both short notation (AB:BC) and long notation (A:B:C:AB:BC).
  ## Long notation is simplified by removing subsumed relations.
  ##
  ## Example:
  ##   let model = mgr.makeModel("AB:BC:C")  # Three relations
  ##   let indep = mgr.makeModel("A:B:C")    # Independence model
  let existing = mgr.modelCache.get(name)
  if existing.isSome:
    return existing.get

  var relations: seq[Relation]
  let parts = name.split(':')

  for part in parts:
    var varIndices: seq[VariableIndex]
    for c in part:
      # Look up variable by abbreviation
      let idxOpt = mgr.varList.findByAbbrev($c)
      if idxOpt.isSome:
        varIndices.add(idxOpt.get)
    if varIndices.len > 0:
      let rel = mgr.getRelation(varIndices)
      relations.add(rel)

  # Simplify: remove relations that are subsumed by other relations
  # A relation R1 is subsumed by R2 if all variables in R1 are also in R2
  var maximalRelations: seq[Relation]
  for i in 0..<relations.len:
    var isSubsumed = false
    for j in 0..<relations.len:
      if i != j:
        # Check if relations[i] is subsumed by relations[j]
        if relations[i].variableCount < relations[j].variableCount:
          var allContained = true
          for varIdx in relations[i].varIndices:
            if not relations[j].hasVariable(varIdx):
              allContained = false
              break
          if allContained:
            isSubsumed = true
            break
    if not isSubsumed:
      maximalRelations.add(relations[i])

  var model = initModel(maximalRelations)
  mgr.modelCache.put(model, mgr.varList)


proc parseModel*(mgr: var VBManager; name: string): Model =
  ## Alias for `makeModel` - parse a model from string notation.
  ## Preferred name for new code as it better describes the operation.
  mgr.makeModel(name)


# ============ Reference Model Validation ============

type
  ModelValidationResult* = object
    ## Result of validating a reference model string
    isValid*: bool
    model*: Model
    errorMessage*: string


proc validateReferenceModel*(mgr: var VBManager; notation: string): ModelValidationResult =
  ## Validate and parse a reference model notation string.
  ##
  ## Returns a ModelValidationResult with:
  ## - isValid: true if notation is valid or empty
  ## - model: the parsed Model (empty if notation was empty)
  ## - errorMessage: description of validation error (empty if valid)
  ##
  ## Empty or whitespace-only notation is valid and means "use default".
  ## Invalid variable abbreviations will result in an error.
  ##
  ## Example:
  ##   let result = mgr.validateReferenceModel("AB:BC")
  ##   if result.isValid:
  ##     let model = result.model
  ##   else:
  ##     echo result.errorMessage

  # Empty or whitespace-only is valid (means use default)
  let trimmed = notation.strip()
  if trimmed.len == 0:
    return ModelValidationResult(
      isValid: true,
      model: initModel(@[]),
      errorMessage: ""
    )

  # Validate each character in the notation before parsing
  let parts = trimmed.split(':')
  for part in parts:
    for c in part:
      let idxOpt = mgr.varList.findByAbbrev($c)
      if idxOpt.isNone:
        return ModelValidationResult(
          isValid: false,
          model: initModel(@[]),
          errorMessage: "Unknown variable abbreviation: " & $c
        )

  # All characters valid - parse the model
  let model = mgr.parseModel(trimmed)
  ModelValidationResult(
    isValid: true,
    model: model,
    errorMessage: ""
  )


# ============ Statistics Computation ============

# Forward declaration for makeFitTable (defined later, used by computeH for loops)
proc makeFitTable*(mgr: var VBManager; model: Model): coretable.ContingencyTable {.raises: [JunctionTreeError, ConvergenceError, ComputationError].}

proc computeH*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute entropy H for a model
  ## For loopless models, uses algebraic method; for loops, uses IPF
  if not hasLoops(model, mgr.varList):
    # Algebraic method using inclusion-exclusion
    result = modelH(model, mgr.varList, mgr.normalizedData)
  else:
    # Use IPF-fitted distribution for loop models
    let fitTable = mgr.makeFitTable(model)
    result = entropy(fitTable)


proc computeT*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute transmission T for a model
  ## T = H(top) - H(model)
  let hTop = mgr.computeH(mgr.topRef)
  let hModel = mgr.computeH(model)
  hTop - hModel


proc computeDF*(mgr: var VBManager; model: Model): int64 =
  ## Compute degrees of freedom for a model
  modelDF(model, mgr.varList)


proc computeDDF*(mgr: var VBManager; model: Model): int64 =
  ## Compute delta DF (difference from top model)
  let dfTop = mgr.computeDF(mgr.topRef)
  let dfModel = mgr.computeDF(model)
  dfTop - dfModel


proc computeLR*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute likelihood ratio statistic
  ## LR = 2 * N * ln(2) * (H_model - H_saturated)
  ## Measures the "extra uncertainty" in the model vs perfect fit
  ## LR = 0 for saturated model, LR > 0 for simpler models
  let hSat = mgr.computeH(mgr.topRef)
  let hModel = mgr.computeH(model)
  likelihoodRatio(mgr.sampleSize, hModel, hSat)


proc computeAIC*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute AIC
  let lr = mgr.computeLR(model)
  let df = mgr.computeDF(model).float64
  aic(lr, df)


proc computeBIC*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute BIC using DDF (delta DF from saturated model)
  ## This properly rewards simpler models for parsimony
  let lr = mgr.computeLR(model)
  let ddf = mgr.computeDDF(model).float64
  bic(lr, ddf, mgr.sampleSize)


proc computeCondH*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute conditional entropy H(DV|IVs) for a directed system
  ## H(DV|IVs) = H(model) - H(IVs)
  ## This is the uncertainty in DV that remains after knowing the IVs
  if not mgr.varList.isDirected:
    return 0.0

  # Get IV indices
  var ivIndices: seq[VariableIndex]
  for vi, v in mgr.varList.pairs:
    if not v.isDependent:
      ivIndices.add(vi)

  # H(model) is the entropy of the fitted distribution
  let hModel = mgr.computeH(model)

  # H(IVs) is the marginal entropy of IVs
  let ivProj = mgr.normalizedData.project(mgr.varList, ivIndices)
  let hIV = entropy(ivProj)

  # H(DV|IVs) = H(DV, IVs) - H(IVs) = H(model) - H(IVs)
  # For the model, the joint entropy is the model entropy
  result = hModel - hIV


proc computeCondDH*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute conditional delta H: the reduction in uncertainty about DV due to IVs
  ## cond_dH = H(DV) - H(DV|IVs) = H(DV) - H(model) + H(IVs)
  ## This measures how much the model reduces uncertainty about DV
  if not mgr.varList.isDirected:
    return 0.0

  # Get DV index and compute H(DV)
  var dvIndex: VariableIndex
  for vi, v in mgr.varList.pairs:
    if v.isDependent:
      dvIndex = vi
      break

  let dvProj = mgr.normalizedData.project(mgr.varList, @[dvIndex])
  let hDV = entropy(dvProj)

  # H(DV|IVs) from the model
  let condH = mgr.computeCondH(model)

  # Reduction in uncertainty
  result = hDV - condH


proc computeCoverage*(mgr: var VBManager): float64 =
  ## Compute percent coverage: fraction of state space with observations
  ## coverage = (number of observed states) / (total possible states)
  let totalStates = mgr.varList.stateSpace
  let observedStates = mgr.inputData.len

  if totalStates > 0:
    result = observedStates.float64 / totalStates.float64
  else:
    result = 0.0


proc computeIncrAlpha*(mgr: var VBManager; model: Model; progenitor: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute incremental alpha (p-value) for comparing model to progenitor
  ## Tests whether the difference in fit is statistically significant
  ## Uses the difference in LR and DF to compute p-value
  let lrModel = mgr.computeLR(model)
  let lrProg = mgr.computeLR(progenitor)
  let dfModel = mgr.computeDF(model)
  let dfProg = mgr.computeDF(progenitor)

  # The test statistic is the difference in LR
  let deltaLR = abs(lrProg - lrModel)

  # Degrees of freedom is the difference in DF
  let deltaDf = abs(dfModel - dfProg)

  if deltaDf > 0:
    result = chiSquaredPValue(deltaLR, deltaDf.float64)
  else:
    result = 1.0


proc makeFitTable*(mgr: var VBManager; model: Model): coretable.ContingencyTable {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute fitted distribution for a model
  ## Uses algebraic method for loopless models, IPF for models with loops
  let fitInfo = mgrfitting.fitModelTable(mgr.normalizedData, model, mgr.varList)
  fitInfo.fitTable


proc makeFitTableWithInfo*(mgr: var VBManager; model: Model): (coretable.ContingencyTable, int, float64) {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute fitted distribution and return fitting info
  ## Returns (fitTable, iterations, error)
  ## For loopless models using BP: iterations = 2 (collect + distribute), error = 0
  let fitInfo = mgrfitting.fitModelTable(mgr.normalizedData, model, mgr.varList)
  (fitInfo.fitTable, fitInfo.iterations, fitInfo.error)


proc computeFitH*(mgr: var VBManager; model: Model): float64 {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute entropy of the fitted distribution
  let fitTable = mgr.makeFitTable(model)
  entropy(fitTable)


# ============ Relation Metrics ============

proc computeRelationMarginal*(mgr: var VBManager; rel: Relation): coretable.ContingencyTable =
  ## Compute marginal distribution for a relation
  mgr.normalizedData.project(mgr.varList, rel.varIndices)


proc computeRelationH*(mgr: var VBManager; rel: Relation): float64 =
  ## Compute entropy of marginal distribution for a relation
  let marginal = mgr.computeRelationMarginal(rel)
  entropy(marginal)


proc computeRelationIndepH*(mgr: var VBManager; rel: Relation): float64 =
  ## Compute entropy of independence model for variables in relation
  ## H_indep = sum of individual variable entropies
  result = 0.0
  for varIdx in rel.varIndices:
    # Compute marginal for this single variable
    let singleRel = initRelation(@[varIdx])
    result += mgr.computeRelationH(singleRel)


proc computeRelationT*(mgr: var VBManager; rel: Relation): float64 =
  ## Compute transmission for a relation
  ## T = H_indep - H_rel
  let hIndep = mgr.computeRelationIndepH(rel)
  let hRel = mgr.computeRelationH(rel)
  hIndep - hRel


proc getRelationMetrics*(mgr: var VBManager; rel: Relation): RelationMetrics =
  ## Compute all metrics for a relation
  result.relation = rel
  result.h = mgr.computeRelationH(rel)
  result.t = mgr.computeRelationT(rel)
  result.df = rel.degreesOfFreedom(mgr.varList)

  # Compute LR and P2 for this relation
  # LR measures deviation from independence: LR = 2*N*ln(2)*(H_indep - H_actual)
  let hIndep = mgr.computeRelationIndepH(rel)
  result.lr = likelihoodRatio(mgr.sampleSize, hIndep, result.h)

  # For P2, we need observed and expected (independence) marginals
  let observed = mgr.computeRelationMarginal(rel)

  # Build independence distribution for this relation
  var expected = coretable.initTable(mgr.varList.keySize)
  # Get individual variable marginals
  var varMarginals: seq[coretable.ContingencyTable] = @[]
  for varIdx in rel.varIndices:
    let singleRel = initRelation(@[varIdx])
    varMarginals.add(mgr.computeRelationMarginal(singleRel))

  # Build product distribution
  for tup in observed:
    var prob = 1.0
    for i, varIdx in rel.varIndices:
      # Find this variable's value in the tuple
      let varVal = tup.key.getValue(mgr.varList, varIdx)
      # Find corresponding probability in marginal
      for margTup in varMarginals[i]:
        if margTup.key.getValue(mgr.varList, varIdx) == varVal:
          prob *= margTup.value
          break
    expected.add(tup.key, prob)
  expected.sort()

  result.p2 = pearsonChiSquared(observed, expected, mgr.sampleSize)


proc getModelRelationMetrics*(mgr: var VBManager; model: Model): seq[RelationMetrics] =
  ## Compute metrics for all relations in a model
  result = @[]
  for rel in model.relations:
    result.add(mgr.getRelationMetrics(rel))


proc computeResiduals*(mgr: var VBManager; model: Model): coretable.ContingencyTable {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Compute residuals (observed - fitted) for each cell
  let fitTable = mgr.makeFitTable(model)
  mgrfitting.computeResiduals(mgr.normalizedData, fitTable, mgr.varList)


proc fitModel*(mgr: var VBManager; model: Model): FitResult {.raises: [JunctionTreeError, ConvergenceError, ComputationError].} =
  ## Fit a model and compute all statistics

  # Get fit table with IPF info
  let (fitTable, ipfIter, ipfErr) = mgr.makeFitTableWithInfo(model)

  result.fitTable = fitTable
  result.ipfIterations = ipfIter
  result.ipfError = ipfErr
  result.hasLoops = hasLoops(model, mgr.varList)

  # Compute statistics
  result.h = entropy(fitTable)
  result.df = mgr.computeDF(model)
  result.ddf = mgr.computeDDF(model)

  # Transmission: H(data) - H(model)
  let hData = entropy(mgr.normalizedData)
  result.t = hData - result.h

  # Likelihood ratio vs top (saturated) model
  # LR = 2 * N * ln(2) * (H_model - H_saturated)
  result.lr = likelihoodRatio(mgr.sampleSize, result.h, hData)

  # Pearson chi-squared (P2)
  # P2 = Σ (O - E)² / E
  result.p2 = pearsonChiSquared(mgr.normalizedData, fitTable, mgr.sampleSize)

  # p-value using chi-squared distribution
  if result.ddf > 0:
    result.alpha = chiSquaredPValue(result.lr, result.ddf.float64)
  else:
    result.alpha = 1.0

  # Statistical power (beta)
  # Power = P(reject H0 | H1 true) = 1 - P(Type II error)
  # Uses non-central chi-squared with LR as noncentrality parameter
  if result.ddf > 0:
    result.beta = computePower(result.ddf.float64, result.lr, 0.05)
  else:
    result.beta = 1.0

  # AIC and BIC (BIC uses DDF for proper parsimony reward)
  result.aic = aic(result.lr, result.df.float64)
  result.bic = bic(result.lr, result.ddf.float64, mgr.sampleSize)

  # Conditional entropy (directed systems only)
  result.condH = mgr.computeCondH(model)
  result.condDH = mgr.computeCondDH(model)

  # Coverage
  result.coverage = mgr.computeCoverage()


# ============ Search ============

proc searchOneLevelUp(mgr: var VBManager; model: Model): seq[Model] =
  ## Generate all parent models (one level up in lattice)
  ## For VB neutral: find pairs of variables that appear in exactly one relation
  ##   and combine them
  ## For VB directed: add IVs to predictive components
  result = @[]

  if mgr.varList.isDirected:
    # Directed upward search
    # For each IV not in a predictive relation, add it
    var indOnlyRelIdx = none(int)
    for i in 0..<model.relationCount:
      if model.relations[i].isIndependentOnly(mgr.varList):
        indOnlyRelIdx = some(i)
        break

    if indOnlyRelIdx.isNone:
      return  # Malformed model

    let ivRelIdx = indOnlyRelIdx.get

    # For each variable, try adding to each non-IV relation
    for varIdx in 0..<mgr.varList.len:
      let vIdx = VariableIndex(varIdx)
      if mgr.varList[vIdx].isDependent:
        continue  # Skip DV

      for relIdx in 0..<model.relationCount:
        if relIdx == ivRelIdx:
          continue

        let rel = model.relations[relIdx]
        if not rel.containsVariable(vIdx):
          # Add this variable to the relation
          var newVars = rel.varIndices
          newVars.add(vIdx)
          let newRel = mgr.getRelation(newVars)

          var newRels: seq[Relation]
          for i in 0..<model.relationCount:
            if i == relIdx:
              newRels.add(newRel)
            else:
              newRels.add(model.relations[i])

          var newModel = initModel(newRels)
          newModel = mgr.modelCache.put(newModel, mgr.varList)
          result.add(newModel)

  else:
    # Neutral upward search
    # Find pairs of variables in different relations and link them
    let varCount = mgr.varList.len

    for i in 0..<varCount:
      for j in (i+1)..<varCount:
        let vi = VariableIndex(i)
        let vj = VariableIndex(j)

        # Check if this pair is in exactly one relation
        var containCount = 0
        var containIdx = -1
        for relIdx in 0..<model.relationCount:
          let rel = model.relations[relIdx]
          if rel.containsVariable(vi) and rel.containsVariable(vj):
            containCount += 1
            containIdx = relIdx

        # If pair not in any relation, we can add a relation containing them
        if containCount == 0:
          # Find relations containing each variable and combine
          var newVars = @[vi, vj]
          # Find overlap between relations containing vi and vj
          for relIdx in 0..<model.relationCount:
            let rel = model.relations[relIdx]
            if rel.containsVariable(vi) or rel.containsVariable(vj):
              for v in rel.varIndices:
                if v != vi and v != vj and v notin newVars:
                  newVars.add(v)

          let newRel = mgr.getRelation(newVars)

          var newRels: seq[Relation]
          for rel in model.relations:
            newRels.add(rel)
          newRels.add(newRel)

          var newModel = initModel(newRels)
          # Check if model is different and valid
          if newModel.printName(mgr.varList) != model.printName(mgr.varList):
            newModel = mgr.modelCache.put(newModel, mgr.varList)
            # Check for duplicates
            var isDup = false
            for existing in result:
              if existing.printName(mgr.varList) == newModel.printName(mgr.varList):
                isDup = true
                break
            if not isDup:
              result.add(newModel)


proc searchOneLevelDown(mgr: var VBManager; model: Model): seq[Model] =
  ## Generate all child models (one level down in lattice)
  ## For each relation with >1 variable, remove one variable
  result = @[]

  for relIdx in 0..<model.relationCount:
    let rel = model.relations[relIdx]

    # Skip trivial (single-variable) relations
    if rel.variableCount <= 1:
      continue

    # For directed systems, skip IV-only relations
    if mgr.varList.isDirected and rel.isIndependentOnly(mgr.varList):
      continue

    # Create child model by replacing this relation with children
    for varToRemove in rel.varIndices:
      # Create child relation without this variable
      var childVars: seq[VariableIndex]
      for v in rel.varIndices:
        if v != varToRemove:
          childVars.add(v)

      if childVars.len == 0:
        continue

      let childRel = mgr.getRelation(childVars)

      # Build new model with this relation replaced
      var newRels: seq[Relation]
      for i in 0..<model.relationCount:
        if i == relIdx:
          newRels.add(childRel)
        else:
          newRels.add(model.relations[i])

      # Also need to add the removed variable as its own relation
      let singleRel = mgr.getRelation(@[varToRemove])
      newRels.add(singleRel)

      var newModel = initModel(newRels)
      newModel = mgr.modelCache.put(newModel, mgr.varList)

      # Check for duplicates
      var isDup = false
      for existing in result:
        if existing.printName(mgr.varList) == newModel.printName(mgr.varList):
          isDup = true
          break
      if not isDup:
        result.add(newModel)


proc searchOneLevel*(mgr: var VBManager; model: Model): seq[Model] =
  ## Generate neighbor models one level in the search direction
  if mgr.searchDirection == Direction.Ascending:
    mgr.searchOneLevelUp(model)
  else:
    mgr.searchOneLevelDown(model)


# ============ Cache Statistics ============

proc getRelationCacheStats*(mgr: VBManager): CacheStats =
  ## Get statistics for the relation cache
  mgr.relCache.stats


proc getModelCacheStats*(mgr: VBManager): CacheStats =
  ## Get statistics for the model cache
  mgr.modelCache.stats


proc getCombinedCacheStats*(mgr: VBManager): CacheStats =
  ## Get combined statistics for both caches
  let rel = mgr.relCache.stats
  let mdl = mgr.modelCache.stats
  CacheStats(
    hits: rel.hits + mdl.hits,
    misses: rel.misses + mdl.misses,
    entries: rel.entries + mdl.entries
  )


proc getCacheHitRate*(mgr: VBManager): float64 =
  ## Get combined hit rate for both caches (0.0 to 1.0)
  let combined = mgr.getCombinedCacheStats()
  combined.hitRate()


proc resetCacheStats*(mgr: var VBManager) =
  ## Reset cache statistics counters without clearing caches
  mgr.relCache.resetStats()
  mgr.modelCache.resetStats()


proc clearCaches*(mgr: var VBManager) =
  ## Clear all caches and reset statistics
  mgr.relCache.clear()
  mgr.modelCache.clear()


# ============ Profiling ============

proc isProfilingEnabled*(mgr: VBManager): bool =
  ## Check if profiling is enabled for this manager
  mgr.profiler != nil and mgr.profiler.config.granularity != pgNone

proc enableProfiling*(mgr: var VBManager; config = initProfileConfig(pgSummary)) =
  ## Enable profiling on an existing manager
  ## Creates a new ProfileAccumulator with the given config
  mgr.profiler = initProfileAccumulator(config)

proc disableProfiling*(mgr: var VBManager) =
  ## Disable profiling on an existing manager
  mgr.profiler = nil

proc getResourceProfile*(mgr: VBManager): ResourceProfile =
  ## Get the current resource profile from the manager
  ## Returns an empty profile if profiling is not enabled
  if mgr.profiler != nil:
    result = mgr.profiler.toResourceProfile()
    # Add cache stats from manager
    let cacheStats = mgr.getCombinedCacheStats()
    result.cacheStats = ProfileCacheStats(
      hits: cacheStats.hits,
      misses: cacheStats.misses,
      entries: cacheStats.entries
    )
  else:
    result = ResourceProfile()

proc recordOperation*(mgr: var VBManager; name: string; durationNs: int64) =
  ## Record an operation timing if profiling is enabled
  ## Profiling errors are silently ignored to not affect main code path
  if mgr.profiler != nil:
    try:
      mgr.profiler.recordOp(name, durationNs)
    except KeyError:
      discard  # Profiling should not affect main code path

proc recordFitOperation*(mgr: var VBManager; fitInfo: mgrfitting.FitInfo) =
  ## Record a fit operation with detailed timing from FitInfo
  ## Automatically categorizes by fit type and records breakdown
  ## Profiling errors are silently ignored to not affect main code path
  if mgr.profiler != nil:
    try:
      # Record overall fit time
      mgr.profiler.recordOp("fit_total", fitInfo.fitTimeNs)

      # Record by fit type
      case fitInfo.fitType
      of mgrfitting.ftSaturated:
        mgr.profiler.recordOp("fit_saturated", fitInfo.fitTimeNs)
      of mgrfitting.ftIndependence:
        mgr.profiler.recordOp("fit_independence", fitInfo.fitTimeNs)
      of mgrfitting.ftLoopless:
        mgr.profiler.recordOp("fit_loopless", fitInfo.fitTimeNs)
        if fitInfo.bpCollectNs > 0:
          mgr.profiler.recordOp("bp_collect", fitInfo.bpCollectNs)
        if fitInfo.bpDistributeNs > 0:
          mgr.profiler.recordOp("bp_distribute", fitInfo.bpDistributeNs)
      of mgrfitting.ftIPF:
        mgr.profiler.recordOp("fit_ipf", fitInfo.fitTimeNs)
        if fitInfo.ipfTotalNs > 0:
          mgr.profiler.recordOp("ipf_total", fitInfo.ipfTotalNs)
        # Record iteration count for IPF
        mgr.profiler.recordOp("ipf_iterations", fitInfo.iterations.int64)
    except KeyError:
      discard  # Profiling should not affect main code path


# Re-export analysis functions for backwards compatibility
import analysis
export analysis
export CacheStats
export ProfileConfig, ProfileGranularity, ProfileAccumulator, ResourceProfile
export initProfileConfig, initProfileAccumulator, toResourceProfile, toJson

