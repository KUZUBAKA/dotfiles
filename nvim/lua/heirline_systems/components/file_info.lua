local M = {}

M.filetype = {
  init = function(self) self.ft = vim.bo[0].filetype or vim.bo[0].buftype end,
  provider = function(self) return self.ft end,
}

M.devicon = {
  init = function(self)
    local ft = vim.bo[0].filetype or vim.bo[0].buftype
    local icon, color = require("nvim-web-devicons").get_icon_color_by_filetype(ft, { default = true })
    self.icon = icon
    self.icon_color = color
  end,

  hl = function(self)
    return { fg = self.icon_color }
  end,

  provider = function(self)
    if self.icon == nil then return " " end
    return self.icon
  end,
}

M.encoding = {
  init = function(self) self.encoding = vim.opt.fileencoding:get() end,
  provider = function(self) return self.encoding end
}

return M
