return {
 'saecki/crates.nvim',
 tag = 'stable',
 config = function()
  require('crates').setup({
   lsp = {
    enabled = true,
    actions = true,
    completion = true,
    hover = true,
   },
   null_ls = { enabled = false },

   on_attach = function ()
    require("crates").hide()
   end,
  })
 end,
}
