## Result types for OCCAM analysis
## Extracted from vb.nim for better module organization

{.push raises: [].}

import types
import table as coretable
import relation

type
  FitResult* = object
    ## Result of fitting a model
    fitTable*: coretable.ContingencyTable   # Fitted probability distribution
    h*: float64                  # Entropy of fitted distribution
    t*: float64                  # Transmission
    df*: int64                   # Degrees of freedom
    ddf*: int64                  # Delta DF (vs top)
    lr*: float64                 # Likelihood ratio (vs top)
    p2*: float64                 # Pearson chi-squared
    alpha*: float64              # p-value
    beta*: float64               # Statistical power (1 - Type II error probability)
    aic*: float64                # AIC
    bic*: float64                # BIC
    condH*: float64              # Conditional entropy H(DV|IVs) - directed only
    condDH*: float64             # Uncertainty reduction H(DV) - H(DV|IVs) - directed only
    coverage*: float64           # Percent coverage (observed/total states)
    ipfIterations*: int          # Iterations (0 if algebraic)
    ipfError*: float64           # Final IPF error
    hasLoops*: bool              # Whether model has loops


  RelationMetrics* = object
    ## Metrics for a single relation
    relation*: Relation
    h*: float64       # Entropy of marginal
    t*: float64       # Transmission (H_indep - H_rel)
    df*: int64        # Degrees of freedom
    lr*: float64      # Likelihood ratio
    p2*: float64      # Pearson chi-squared


  ConditionalDVTable* = object
    ## Table showing P(DV|IVs) for each IV state combination
    ivStates*: seq[seq[int]]        # Each IV state combination
    ivIndices*: seq[VariableIndex]  # IV variable indices
    dvProbs*: seq[seq[float64]]     # P(DV=k | IV state) for each DV value
    predictions*: seq[int]          # Predicted DV for each IV state
    correctCounts*: seq[int]        # Count correct per IV state
    totalCounts*: seq[int]          # Total count per IV state
    percentCorrect*: float64        # Overall percent correct


  ConfusionMatrix* = object
    ## Confusion matrix comparing actual vs predicted DV values
    matrix*: seq[seq[int]]          # NxN: Actual (rows) vs Predicted (cols)
    labels*: seq[string]            # DV value labels
    accuracy*: float64              # Overall accuracy
    perClassPrecision*: seq[float64]  # Precision per class
    perClassRecall*: seq[float64]     # Recall per class
