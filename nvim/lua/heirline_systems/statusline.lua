local utils = require("heirline.utils")
local align = { provider = "%=", }
local whitespace = { provider = " " }
local sep = require("heirline_systems.separators")
local com = require("heirline_systems.components_manager")

local left_block = {
 -- com.current_mode,
 { hl = "HlFilePath", com.file_path },
 { hl = "HlSepFPR",   provider = sep.right_thin },
 { hl = "HlFileType", { whitespace, com.file_devicon } },
 { hl = "HlFileType", { com.file_type, utils.clone(whitespace), } },
 { hl = "HlSepFTR",   provider = sep.right_filled },
 align,
}
local right_block = {
 -- { hl = "HlSepDate",        provider = sep.left_filled },
 -- { hl = "HlDate",           { utils.clone(whitespace), com.date, utils.clone(whitespace), } },
 { hl = "HlCursorPosSep",   provider = sep.left_filled },
 { hl = "HlCursorPos",      { utils.clone(whitespace), com.cursor_pos, utils.clone(whitespace) } },
 { hl = "HlCharsSep",       provider = sep.left_filled },
 { hl = "HlChars",          { utils.clone(whitespace), com.chars, utils.clone(whitespace) } },
 { hl = "HlSelChars",       { utils.clone(whitespace), com.sel_chars, utils.clone(whitespace) } },
 { hl = "HlDiagnosticsSep", provider = sep.left_filled },
 { hl = "HlDiagnostics",    { utils.clone(whitespace), com.diagnostics } },
}


return {
 hl = "StatusLine",
 condition = function()
  return not vim.tbl_contains({ "oil" }, vim.bo[0].filetype)
 end,
 left_block,
 right_block,
}
