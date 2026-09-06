return {
 "ray-x/lsp_signature.nvim",
 event = "LspAttach",
 keys = { { "<leader>sk", function() require("lsp_signature").toggle_float_win() end, desc = "Toggle signature" } },
 config = function()
  require("lsp_signature").setup({
   auto_open = false,
   ignore_error = function(e) return e and e.code == -32801 end,
   hint_enable = false,
   handler_opts = {
    border = "rounded",
   },
  })
 end,
}
