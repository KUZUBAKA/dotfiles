return {
  "mfussenegger/nvim-lint",
  event = { "BufWritePost", "BufReadPost" },
  config = function()
    local lint = require("lint")

    lint.linters_by_ft = {
      python = { "flake8" },
      javascript = { "eslint_d" },
    }

    table.insert(lint.linters.flake8.args, 1, "--indent-size=2")

    vim.api.nvim_create_autocmd({ "BufWrite", "BufReadPost" }, {
      callback = function() lint.try_lint() end,
    })
  end,
}
