return {
  "rebelot/heirline.nvim",
  event = "UiEnter",
  config = function()
    require("heirline").setup({
      -- statusline = require("heirline_systems.statusline"),
      -- tabline = require("heirline_systems.tabline"),
      statuscolumn = require("heirline_systems.statuscolumn"),
      winbar = require("heirline_systems.statusline"),
      opts = {
        disable_winbar_cb = function(args)
          local buftype = vim.bo[args.buf].buftype
          local disable_buftypes = {
            "nofile",
            "help",
            "terminal",
            "quickfix",
            "acwrite",
          }
          if vim.tbl_contains(disable_buftypes, buftype) then return true end
        end,
      },
    })
  end,
}
