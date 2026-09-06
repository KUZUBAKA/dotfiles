return {
 enabled = false,
 "folke/which-key.nvim",
 event = "VeryLazy",
 keys = {
  {
   "<BS>",
   function() require("which-key").show({ global = true }) end,
   desc = "現バッファのKeymap一覧",
  },
  {
   "<C-g>",
   "<Cmd>echo ''CR<>",
   desc = "Close",
  }
 },
 opts = {
  presets = "modern",
  win = { border = "rounded" },
  delay = function()
   local no_show_filetype = { "plaintext", "markdown" }
   if vim.tbl_contains(no_show_filetype, vim.bo.filetype) then return 1000000000000 end
   return 200
  end,
  triggers = { { "<auto>", mode = "n" } },
  spec = { { "<leader>f", group = "Find / Snack" }, { "<leader>fa", group = "Find / Hidden込み検索" }, { "<leader>t", group = "Terminal" } },
 },
}
