local errors = {
 hl = "DiagnosticError",
 update = { "DiagnosticChanged", "BufEnter" },
 provider = function()
  local count = vim.diagnostic.count(0)
  return "" .. (count[vim.diagnostic.severity.ERROR] or 0)
 end
}


local warnings = {
 hl = "DiagnosticWarn",
 update = { "DiagnosticChanged", "BufEnter" },
 provider = function()
  local count = vim.diagnostic.count(0)
  return "" .. (count[vim.diagnostic.severity.WARN] or 0)
 end
}


local hints = {
 hl = "DiagnosticHint",
 update = { "DiagnosticChanged", "BufEnter" },
 provider = function()
  local count = vim.diagnostic.count(0)
  return "" .. (count[vim.diagnostic.severity.HINT] or 0)
 end
}

local com_clone = require("heirline.utils").clone
local separator = {
 provider = " "
}

local result = {


 errors,
 separator,
 warnings,
 com_clone(separator),
 hints,
}
return result
