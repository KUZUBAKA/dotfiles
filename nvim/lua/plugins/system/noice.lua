return {
 "folke/noice.nvim",
 event = "VeryLazy",
 dependencies = { "MunifTanjim/nui.nvim" },
 merge_duplicates = false,
 opts = {
  merge_duplicates = false,
  cmdline = { enabled = true },
  notify = { enabled = false },
  messages = {
   enabled = true,
   view_search = false,
  },
  popupmenu = { enabled = false },
  lsp = {
   progress = { enabled = false },
   hover = { enabled = false },
   signature = { enabled = false },
   override = {
    ["vim.lsp.util.convert_input_to_markdown_lines"] = false,
    ["vim.lsp.util.stylize_markdown"]                = false,
   },
  },
 }
}
