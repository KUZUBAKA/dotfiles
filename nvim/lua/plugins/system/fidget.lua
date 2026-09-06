return {
 enabled = true,
 "j-hui/fidget.nvim",
 config = function()
  local progress = require('fidget.progress').handle.create({
   title = 'Processing...',
  })
  progress:finish()

  require("fidget").setup({})
 end
}
