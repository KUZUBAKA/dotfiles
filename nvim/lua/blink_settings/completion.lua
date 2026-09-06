return {
  menu = {
    border = "rounded",
    auto_show = function()
      local no_auto_show_filetypes = {
        "plaintext",
        "markdown",
      }

      local current_filetype = vim.bo.filetype

      if vim.tbl_contains(no_auto_show_filetypes, current_filetype) then return false end
      return true
    end,
  }
}
