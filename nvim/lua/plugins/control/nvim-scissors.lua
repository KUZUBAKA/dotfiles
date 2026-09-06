return {
  "chrisgrieser/nvim-scissors",
  event = "VeryLazy",
  keys = {
    { "<leader>sa", function() require("scissors").addNewSnippet() end, desc = "Snippet Add" },
    { "<leader>se", function() require("scissors").editSnippet() end,   desc = "Snippet Edit" },
  },
  opts = {
    snippetDir = vim.fn.stdpath("config") .. "/snippets",
  },
}
