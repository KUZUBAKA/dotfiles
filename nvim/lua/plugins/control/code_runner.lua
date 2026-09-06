return {
  "CRAG666/code_runner.nvim",
  event = "VeryLazy",
  keys = {
    { "<leader>rr", function() require("code_runner").run_code() end, desc = "Code run" },
  },
  opts = {
    mode = "toggleterm",
    focus = true,
    float = {
      border = "rounded",
    },
    filetype = {
      python = "python -u",
      rust = "cargo run",
    },
  },
}
