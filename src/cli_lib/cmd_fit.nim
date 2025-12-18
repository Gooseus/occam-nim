## Fit Command Implementation
##
## Implements the fit command for detailed single-model analysis

import std/[strformat, strutils]
import ../occam/core/types
import ../occam/core/variable
import ../occam/core/model
import ../occam/core/relation
import ../occam/core/table
import ../occam/core/key
import ../occam/io/parser
import ../occam/manager/vb
import formatting


proc fit*(input: string;
          model: string;
          compare = "";
          residuals = false;
          conditionalDv = false;
          confusionMatrix = false;
          verbose = false): int =
  ## Fit a single model and display detailed statistics
  ##
  ## Arguments:
  ##   input: Path to JSON data file
  ##   model: Model specification (e.g., "AB:BC" or "AB:BC:AC")
  ##   compare: Model to compare against for incremental alpha (e.g., "AB:C")
  ##   residuals: Show residuals table
  ##   conditionalDv: Show conditional DV table (directed systems)
  ##   confusionMatrix: Show confusion matrix (directed systems)
  ##   verbose: Show detailed output

  if input == "":
    echo "Error: Input file required"
    return 1

  if model == "":
    echo "Error: Model specification required"
    return 1

  # Load data
  let spec = loadDataSpec(input)
  let varList = spec.toVariableList()
  var inputTable = spec.toTable(varList)

  if verbose:
    echo &"Loaded {spec.name}"
    echo &"Variables: {varList.len}"
    echo &"Sample size: {spec.sampleSize}"
    echo ""

  # Create manager
  var mgr = newVBManager(varList, inputTable)

  # Parse and fit the model
  let m = mgr.makeModel(model)
  let modelName = m.printName(varList)

  if verbose:
    echo &"Model: {modelName}"
    echo ""

  let fitResult = mgr.fitModel(m)

  # Print model summary
  printHeader("Model Fit Report")
  echo ""
  echo &"Model:        {modelName}"
  echo &"System:       {(if varList.isDirected: \"Directed\" else: \"Neutral\")}"
  echo &"Has Loops:    {fitResult.hasLoops}"
  if fitResult.hasLoops:
    echo &"IPF Iters:    {fitResult.ipfIterations}"
    echo &"IPF Error:    {formatFloat(fitResult.ipfError, ffScientific, 2)}"
  echo ""

  printSubHeader("Statistics")
  echo &"  H (entropy):     {formatFloat(fitResult.h, ffDecimal, 6)}"
  echo &"  T (transmission):{formatFloat(fitResult.t, ffDecimal, 6)}"
  echo &"  DF:              {fitResult.df}"
  echo &"  DDF (delta DF):  {fitResult.ddf}"
  echo &"  LR (vs top):     {formatFloat(fitResult.lr, ffDecimal, 4)}"
  echo &"  P2 (Pearson):    {formatFloat(fitResult.p2, ffDecimal, 4)}"
  echo &"  Alpha (p-value): {formatFloat(fitResult.alpha, ffDecimal, 6)}"
  echo &"  Beta (power):    {formatFloat(fitResult.beta, ffDecimal, 4)}"
  echo &"  AIC:             {formatFloat(fitResult.aic, ffDecimal, 4)}"
  echo &"  BIC:             {formatFloat(fitResult.bic, ffDecimal, 4)}"

  # Conditional entropy statistics for directed systems
  if varList.isDirected:
    echo ""
    printSubHeader("Conditional Statistics (Directed)")
    echo &"  H(DV|IVs):       {formatFloat(fitResult.condH, ffDecimal, 6)}"
    echo &"  ΔH (reduction):  {formatFloat(fitResult.condDH, ffDecimal, 6)}"

  # Coverage statistic
  echo ""
  printSubHeader("Data Coverage")
  echo &"  Coverage:        {formatFloat(fitResult.coverage * 100.0, ffDecimal, 1)}% ({mgr.getNormalizedData().len}/{varList.stateSpace} states)"
  echo ""

  # Reference model comparison
  printSubHeader("Reference Models")
  echo &"  Top (saturated):  {mgr.topRefModel.printName(varList)}"
  echo &"  Bottom (indep):   {mgr.bottomRefModel.printName(varList)}"
  echo ""

  # Model comparison (incremental alpha)
  if compare != "":
    let compModel = mgr.makeModel(compare)
    let compName = compModel.printName(varList)
    let incrAlpha = mgr.computeIncrAlpha(m, compModel)
    let compFit = mgr.fitModel(compModel)

    printSubHeader("Model Comparison")
    echo &"  Compare to:       {compName}"
    echo &"  Compare DF:       {compFit.df}"
    echo &"  Compare LR:       {formatFloat(compFit.lr, ffDecimal, 4)}"
    echo &"  ΔDF:              {abs(fitResult.df - compFit.df)}"
    echo &"  ΔLR:              {formatFloat(abs(fitResult.lr - compFit.lr), ffDecimal, 4)}"
    echo &"  Incr. Alpha:      {formatFloat(incrAlpha, ffDecimal, 6)}"
    if incrAlpha < 0.05:
      echo "  Significance:     Significant (p < 0.05)"
    else:
      echo "  Significance:     Not significant (p >= 0.05)"
    echo ""

  # Residuals
  if residuals:
    printSubHeader("Residuals (Observed - Fitted)")

    let residualTable = mgr.computeResiduals(m)

    # Print header
    var header = ""
    for i in 0..<varList.len:
      if header.len > 0:
        header.add("  ")
      header.add(varList[VariableIndex(i)].abbrev)
    header.add("    Residual")
    echo header

    # Print each residual
    for tup in residualTable:
      var row = ""
      for i in 0..<varList.len:
        if row.len > 0:
          row.add("  ")
        let val = tup.key.getValue(varList, VariableIndex(i))
        row.add($val)
      row.add(&"    {formatFloat(tup.value, ffDecimal, 6)}")
      echo row

    echo ""

  # Conditional DV Table (for directed systems)
  if conditionalDv:
    if not varList.isDirected:
      echo "Warning: --conditional-dv requires a directed system (DV marker)"
    else:
      printSubHeader("Conditional DV Table P(DV|IVs)")

      let dvTable = mgr.computeConditionalDV(m)

      # Find DV info
      var dvAbbrev = ""
      var dvCard = 0
      for i in 0..<varList.len:
        let v = varList[VariableIndex(i)]
        if v.isDependent:
          dvAbbrev = v.abbrev
          dvCard = v.cardinality.toInt
          break

      # Print header
      var header = ""
      for vi in dvTable.ivIndices:
        if header.len > 0:
          header.add("  ")
        header.add(varList[vi].abbrev)
      header.add("  |")
      for k in 0..<dvCard:
        header.add(&"  P({dvAbbrev}={k})")
      header.add("  | Pred  Correct")
      echo header

      # Print each IV state
      for i in 0..<dvTable.ivStates.len:
        var row = ""
        for j, v in dvTable.ivStates[i]:
          if row.len > 0:
            row.add("  ")
          row.add($v)
        row.add("  |")
        for k in 0..<dvCard:
          row.add(&"  {formatFloat(dvTable.dvProbs[i][k], ffDecimal, 3):<6}")
        row.add(&"  | {dvTable.predictions[i]}     {dvTable.correctCounts[i]}/{dvTable.totalCounts[i]}")
        echo row

      echo ""
      echo &"Percent Correct: {formatFloat(dvTable.percentCorrect * 100.0, ffDecimal, 1)}%"
      echo ""

  # Confusion Matrix (for directed systems)
  if confusionMatrix:
    if not varList.isDirected:
      echo "Warning: --confusion-matrix requires a directed system (DV marker)"
    else:
      printSubHeader("Confusion Matrix")

      let cm = mgr.computeConfusionMatrix(m)
      let dvCard = cm.labels.len

      # Find DV abbrev
      var dvAbbrev = ""
      for i in 0..<varList.len:
        let v = varList[VariableIndex(i)]
        if v.isDependent:
          dvAbbrev = v.abbrev
          break

      # Column header
      echo &"             Predicted {dvAbbrev}"
      var header = "             "
      for k in 0..<dvCard:
        header.add(&"{cm.labels[k]:<8}")
      echo header

      # Rows
      for i in 0..<dvCard:
        var rowLabel = if i == 0: &"Actual {dvAbbrev}  " else: "           "
        var row = rowLabel & &"{cm.labels[i]:<3}"
        for j in 0..<dvCard:
          row.add(&"{cm.matrix[i][j]:<8}")
        echo row

      echo ""
      echo &"Accuracy:  {formatFloat(cm.accuracy, ffDecimal, 3)}"
      echo ""

      # Per-class metrics
      echo "Per-class Metrics:"
      echo &"  Class     Precision  Recall"
      for k in 0..<dvCard:
        echo &"  {cm.labels[k]:<8}  {formatFloat(cm.perClassPrecision[k], ffDecimal, 3):<10} {formatFloat(cm.perClassRecall[k], ffDecimal, 3)}"
      echo ""

  return 0


proc tableCmd*(input: string;
               model: string;
               verbose = false): int =
  ## Display relation metrics for a model
  ##
  ## Arguments:
  ##   input: Path to JSON data file
  ##   model: Model specification (e.g., "AB:BC" or "AB:BC:AC")
  ##   verbose: Show detailed output

  if input == "":
    echo "Error: Input file required"
    return 1

  if model == "":
    echo "Error: Model specification required"
    return 1

  # Load data
  let spec = loadDataSpec(input)
  let varList = spec.toVariableList()
  var inputTable = spec.toTable(varList)

  # Create manager
  var mgr = newVBManager(varList, inputTable)

  # Parse the model
  let m = mgr.makeModel(model)
  let modelName = m.printName(varList)

  printHeader("Relation Metrics")
  echo ""
  echo &"Model:        {modelName}"
  echo &"Sample size:  {int(mgr.sampleSize)}"
  echo ""

  # Get metrics for all relations
  let allMetrics = mgr.getModelRelationMetrics(m)

  # Table header
  printSeparator(72)
  echo "  Relation         H          T     DF         LR         P2"
  printSeparator(72)

  # Table rows
  for metrics in allMetrics:
    let relName = metrics.relation.printName(varList)
    echo &"  {relName:<10} {formatFloat(metrics.h, ffDecimal, 4):>10} {formatFloat(metrics.t, ffDecimal, 4):>10} {metrics.df:>6} {formatFloat(metrics.lr, ffDecimal, 4):>10} {formatFloat(metrics.p2, ffDecimal, 4):>10}"

  printSeparator(72)

  if verbose:
    echo ""
    echo "Legend:"
    echo "  H   = Entropy of marginal (bits)"
    echo "  T   = Transmission: H(indep) - H(relation)"
    echo "  DF  = Degrees of freedom"
    echo "  LR  = Likelihood ratio vs independence"
    echo "  P2  = Pearson chi-squared vs independence"

  return 0
