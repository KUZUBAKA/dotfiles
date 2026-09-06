local M = {}

M.chars = {
  update = { "BufEnter", "CursorMoved", "TextChangedI", "TextChanged" },
  init = function(self) self.chars = vim.fn.wordcount().chars end,
  provider = function(self) return self.chars .. " C" end,
}

M.sel_chars = {
  update = { "ModeChanged", "TextChangedI", "TextChanged", "CursorMoved", "BufEnter" },
  init = function(self)
    self.sel_chars = vim.fn.wordcount().visual_chars
  end,
  provider = function(self)
    if self.sel_chars == nil then
      local lines = vim.api.nvim_buf_line_count(0)
      return lines .. " L"
    end
    return self.sel_chars .. " SelC"
  end
}

return M
