local M = require("blink_settings.manager")

vim.g.path_src = "cwd"

return {
 "saghen/blink.cmp",
 version = "1.*",
 build = "cargo build --release",
 event = { "InsertEnter", "CmdlineEnter" },
 opts = {
 },
 config = function()
  require("blink-cmp").setup({
   keymap = M.keymaps,
   completion = M.completion,
   sources = M.sources,
   cmdline = M.cmdline,
   enabled = function() return not M.in_comment_hide() end,
  })
  vim.api.nvim_create_autocmd({ "CursorMovedI", "TextChanged", "TextChangedI", "ModeChanged" }, {
   callback = function()
    if M.in_comment_hide() then require("blink-cmp").hide() end
   end,
  })
 end,
}
