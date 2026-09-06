return {
 "folke/flash.nvim",
 event = "VeryLazy",
 keys = {
  { "s", function() require("flash").jump() end,       desc = "Flash Jump" },
  { "S", function() require("flash").treesitter() end, desc = "Flash Jump" },
 },
 opts = {
 },
}
