local function is_disabled_file()
  local disabled_filetype = { "grapple" }

  local winid = tonumber(vim.g.statusline_winid)
  if not winid or not vim.api.nvim_win_is_valid(winid) then return false end

  local buf = vim.api.nvim_win_get_buf(winid)
  return not vim.tbl_contains(disabled_filetype, vim.bo[buf].filetype)
end

local wrapppend_line_marker = {
  condition = function()
    return vim.v.virtnum > 0
  end,
  provider = "  ┗",
  hl = "NonText"
}

local number_column = {
  condition = is_disabled_file(),
  provider = function()
    if vim.v.relnum == 0 then
      return vim.v.lnum .. " "
    end

    return vim.v.relnum .. " "
  end,
  hl = function()
    if vim.v.relnum == 0 then return "CursorLineNr" end
    return "LineNr"
  end,
}

local sign_column = {
  provider = "%s",
  hl = "SignColumn"
}

-- local fold_column = {
-- 	provider = "%C",
-- 	hl = "FoldColumn",
-- }

local empty_on_virtual_line = {
  condition = function() return vim.v.virtnum ~= 0 end,
  provider = ""
}

return {
  fallthrough = false,
  wrapppend_line_marker,
  empty_on_virtual_line,
  {
    sign_column,
    number_column,
  }

}
