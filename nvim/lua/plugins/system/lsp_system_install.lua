return {
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    dependencies = {
      "mason-org/mason.nvim",
    },
    opts = {
      ensure_installed = {
        "stylua",
        "biome",
        "black",
        "flake8",
        "eslint_d",
        "prettier",
        "prettierd",
      },
    },
  },
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "b0o/SchemaStore.nvim",
  },
  {
    "neovim/nvim-lspconfig",
  },
  {
    "mason-org/mason.nvim",
    opts = {},
  },
  {
    "b0o/SchemaStore.nvim",
  },
  {
    "neovim/nvim-lspconfig",
  },
}
