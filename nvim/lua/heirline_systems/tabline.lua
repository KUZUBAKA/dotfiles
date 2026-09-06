local utils = require("heirline.utils")
local sep = require("heirline_systems.separators")

local buf_icon = {
 init = function(self)
  local ft = vim.bo[self.bufnr].filetype
  local icon, color = require("nvim-web-devicons").get_icon_color_by_filetype(ft, { default = true })
  self.icon = icon
  self.icon_color = color
 end,

 hl = function(self)
  return { fg = self.icon_color }
 end,

 provider = function(self)
  return self.icon and " " .. self.icon or ""
 end,
}

local buf_name = {
 update = {
  "BufEnter",
  "ModeChanged",
  "TextChanged",
  "TextChangedI",
  "InsertLeave",
  callback = function() vim.api.nvim__redraw({ tabline = true }) end,
 },
 provider = function(self)
  local is_file = vim.api.nvim_buf_get_name(self.bufnr)
  if is_file == nil or is_file == "" then
   local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, 1, false)
   local first_line = (lines and lines[1] ~= "") and lines[1] or "[No Name]"
   local max_len = 10
   if vim.fn.strwidth(first_line) > max_len then return " " .. vim.fn.strcharpart(first_line, 0, 8) end
   return " " .. first_line
  end
  local name = vim.fn.fnamemodify(is_file, ":t")
  return " " .. name
 end,
}

local buf_modified = {
 condition = function(self) return vim.bo[self.bufnr].modified end,
 provider = " ●",
}

local buf_close = {
 condition = function(self)
  return not vim.bo[self.bufnr].modified
 end,
 provider = " ×",
 on_click = {
  callback = function(_, minwid) vim.api.nvim_buf_delete(minwid, { force = false }) end,
  minwid = function(self) return self.bufnr end,
  name = "heirline_tabline_close"
 },
}

local tab_end = {
 provider = sep.right_filled,

 hl = function(self)
  return self.is_active and "HlTabActiveSep" or "HlTabInActiveSep"
 end
}

local tabline_buf = {
 hl = function(self)
  return self.is_active and "TabLineSel" or "TabLine"
 end,
 buf_icon,
 buf_name,
 buf_modified,
 buf_close,
 tab_end,
}

local map = vim.keymap.set

map("n", "<leader>]", function()
 vim.cmd("bnext")
end, { desc = "Next buffer" })

map("n", "<leader>[", function()
 vim.cmd("bprevious")
end, { desc = "Previous buffer" })

map(
 "n",
 "<leader>bd",
 function()
  local is_no_name = vim.bo[0].filetype == nil and true or false
  vim.api.nvim_buf_delete(0, { force = is_no_name })
 end,
 { desc = "Close buffer" }
)

return {
 utils.make_buflist(tabline_buf),
 { provider = "%=" },
}
