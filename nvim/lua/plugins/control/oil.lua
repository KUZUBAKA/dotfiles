return {
  "stevearc/oil.nvim",
  lazy = false,
  dependencies = {
    "nvim-tree/nvim-web-devicons",
  },
  cmd = { "Oil" },
  keys = {
    { "<leader>--", "<CMD>Oil<CR>", desc = "Open parent directory" },
  },
  opts = {
    view_options = { show_hidden = true, },
    skip_confirm_for_simple_edits = true,
  },
}
