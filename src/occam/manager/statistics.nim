## Statistics computation for OCCAM
## Pure functions for model entropy and statistics that don't depend on VBManager
##
## These functions operate on Model, VariableList, and Table directly

{.push raises: [].}

import ../core/types
import ../core/variable
import ../core/table as coretable
import ../core/relation
import ../core/model
import ../math/entropy


# ============ Model Entropy using Inclusion-Exclusion ============

proc modelH*(model: Model; varList: VariableList; data: coretable.ContingencyTable): float64 =
  ## Compute model entropy using inclusion-exclusion principle
  ## For decomposable (loopless) models: H = Σ H(cliques) - Σ H(separators)
  ##
  ## For a chain like AB:BC, the separators are the overlapping variables:
  ## H(AB:BC) = H(AB) + H(BC) - H(B)

  if model.relationCount == 0:
    return 0.0

  if model.relationCount == 1:
    # Single relation - just compute its entropy
    let proj = data.project(varList, model.relations[0].varIndices)
    return entropy(proj)

  # Sum of relation entropies
  result = 0.0
  for rel in model.relations:
    let proj = data.project(varList, rel.varIndices)
    result += entropy(proj)

  # Subtract separator entropies (intersections of consecutive relations in tree)
  # For loopless models, we can find separators by looking at pairwise intersections
  for i in 0..<model.relationCount:
    for j in (i+1)..<model.relationCount:
      let relA = model.relations[i]
      let relB = model.relations[j]

      # Find intersection
      var sepVars: seq[VariableIndex]
      for v in relA.varIndices:
        if relB.containsVariable(v):
          sepVars.add(v)

      if sepVars.len > 0:
        # Subtract separator entropy
        let sepProj = data.project(varList, sepVars)
        result -= entropy(sepProj)


# ============ Relation-level Statistics (Pure Functions) ============

proc relationMarginal*(data: coretable.ContingencyTable; varList: VariableList; rel: Relation): coretable.ContingencyTable =
  ## Compute marginal distribution for a relation
  data.project(varList, rel.varIndices)


proc relationH*(data: coretable.ContingencyTable; varList: VariableList; rel: Relation): float64 =
  ## Compute entropy of marginal distribution for a relation
  let marginal = relationMarginal(data, varList, rel)
  entropy(marginal)


proc relationIndepH*(data: coretable.ContingencyTable; varList: VariableList; rel: Relation): float64 =
  ## Compute entropy of independence model for variables in relation
  ## H_indep = sum of individual variable entropies
  result = 0.0
  for varIdx in rel.varIndices:
    let singleRel = initRelation(@[varIdx])
    result += relationH(data, varList, singleRel)


proc relationT*(data: coretable.ContingencyTable; varList: VariableList; rel: Relation): float64 =
  ## Compute transmission for a relation
  ## T = H_indep - H_rel
  let hIndep = relationIndepH(data, varList, rel)
  let hRel = relationH(data, varList, rel)
  hIndep - hRel


# Export all pure functions
export modelH
export relationMarginal, relationH, relationIndepH, relationT
