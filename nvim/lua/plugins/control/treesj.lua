return {
 "Wansmer/treesj",
 keys = {
  {
   "<leader>m",
   function()
    require("treesj").toggle()
   end,
   desc = "Toggle spilit/join",
  },
 },
 dependencies = {
  "neovim-treesitter/nvim-treesitter",
 },
 opts = function()
  local u = require("treesj.langs.utils")
  return {
   max_join_length = 5000,
   langs = { rust = { match_block = u.set_preset_for_dict({ split = { last_separator = false } }) } },
  }
 end,
}
