return {
  "rachartier/tiny-glimmer.nvim",
  event = "VeryLazy",
  opts = {
    enabled = false,
    default_animation = "fade",
    refresh_interval = 10,
    overwrite = {
      paste = { enabled = true },
      undo = { enabled = true },
      redo = { enabled = true },
      yank = { enabled = true },
    },
  },
}
