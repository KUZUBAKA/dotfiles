return {
 "jinzhongjia/LspUI.nvim",
 branch = "main",
 event = "LspAttach",
 keys = {
  { "<leader>lr", "<cmd>LspUI rename<cr>",          desc = "Rename" },
 },
 opts = {
  inlay_hint = {
   enable = true,
   filter = {
    whitelist = { "rust" },
   }
  },
  rename = {
   enable = true,
   border = "rounded",
   transparency = 0,
   auto_select = false,
  },
  hover = {
   enable = true,
   border = "rounded",
   transparency = 0,
  },
  definition = {
   enable = true,
   border = "rounded",
   transparency = 0,
  },
  diagnostic = {
   enable = false,
  },
 },
}
