return {
"neovim-treesitter/nvim-treesitter",
dependencies = {
"nvim-lua/plenary.nvim",
"neovim-treesitter/treesitter-parser-registry",
},
lazy = false,
build = ":TSUpdate",
config = function()
local install_filetypes = {
"lua",
"python",
"javascript",
"glimmer_javascript",
"rust",
"json",
"yaml",
"xml",
"html",
"html_tags",
"css",
"markdown",
"markdown_inline",
"gdscript",
"vimdoc",
}

require("nvim-treesitter").install(install_filetypes)

vim.api.nvim_create_autocmd("FileType", {
pattern = install_filetypes,
callback = function()
vim.treesitter.start()
if vim.bo.filetype ~= "rust" then
vim.bo.indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
end
end,
})
end,
}
