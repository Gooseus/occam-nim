## CLI Output Formatting Utilities
##
## Provides common formatting functions for CLI output, including:
## - Float formatting with precision control
## - Model statistics display
## - Table formatting

import std/[strformat, strutils]
import ../occam/core/types
import ../occam/core/variable
import ../occam/core/model
import ../occam/manager/vb

# Re-export strutils formatFloat for use with format modes
export strutils.formatFloat


proc fmtFloat*(x: float64; precision: int = 4): string =
  ## Format float with specified precision (shorthand)
  strutils.formatFloat(x, ffDecimal, precision)


proc printModelStats*(model: Model; mgr: var VBManager; varList: VariableList; showLoops = false) =
  ## Print statistics for a model in a single line
  let name = model.printName(varList)
  let df = mgr.computeDF(model)
  let h = mgr.computeH(model)
  let lr = mgr.computeLR(model)
  let aic = mgr.computeAIC(model)
  let bic = mgr.computeBIC(model)
  let loopMark = if showLoops and hasLoops(model, varList): " [LOOP]" else: ""

  echo &"  {name:<20} DF={df:<6} H={fmtFloat(h):<10} LR={fmtFloat(lr):<10} AIC={fmtFloat(aic):<10} BIC={fmtFloat(bic)}{loopMark}"


proc printHeader*(title: string; width = 60) =
  ## Print a section header
  echo title
  echo "=" .repeat(width)


proc printSubHeader*(title: string; width = 60) =
  ## Print a subsection header
  echo title
  echo "-" .repeat(width)


proc printSeparator*(width = 60) =
  ## Print a horizontal separator
  echo "-" .repeat(width)


proc printKeyValue*(key: string; value: string) =
  ## Print a key-value pair with aligned formatting
  echo &"  {key:<14} {value}"


proc printKeyValueNum*(key: string; value: int) =
  ## Print a key-value pair with numeric value
  echo &"  {key:<14} {value}"


proc printKeyValueFloat*(key: string; value: float64; precision = 4) =
  ## Print a key-value pair with float value
  echo &"  {key:<14} {strutils.formatFloat(value, ffDecimal, precision)}"
