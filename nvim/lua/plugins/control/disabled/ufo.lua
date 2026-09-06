return {
 enabled = false,
 "kevinhwang91/nvim-ufo",
 event = "BufReadPost",
 dependencies = { "kevinhwang91/promise-async" },
 keys = {
  { "zR", function() require("ufo").openAllFolds() end, desc = "Open All Folds" },
  { "zM", function() require("ufo").closeAllFolds() end, desc = "Close All Folds" },
 },
 opts = {
  provider_selector = function() return { "lsp", "indent" } end,
 },
}
