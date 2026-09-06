local vo = vim.o
local indent = 1;

vo.encoding = "utf-8"
vo.clipboard = "unnamedplus"
vim.opt.fixeol = false
vim.opt.conceallevel = 0
vim.opt.fileformats = { "unix", "dos" }
vo.timeoutlen = 5000
vo.tabstop = indent
vo.shiftwidth = indent
vo.softtabstop = indent
vo.expandtab = true
vo.foldlevel = 99
vo.foldlevelstart = 99
vo.foldenable = true
vo.report = 999999999
vo.swapfile = false
vim.bo.omnifunc = "syntaxcomplete#Complete"

vim.g.loaded_matchparen = 1
vim.g.markdown_recommended_style = 0
vim.g.rust_recommended_style = false
vim.g.python_recommended_style = 0

-- Leader
vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Filetype Set | Noname == Markdown
vim.api.nvim_create_autocmd("BufEnter", {
callback = function(args)
if vim.bo[args.buf].buftype == "" and vim.bo[args.buf].filetype == "" then vim.cmd("set filetype=markdown") end
end,
})

-- Indent Format
vim.api.nvim_create_autocmd("BufWritePre", {
callback = function()
local v = vim.fn.winsaveview();
pcall(vim.cmd, "silent undojoin");
vim.cmd("keepjumps normal! gg=G");
vim.fn.winrestview(v);
end
})

-- Comment
vim.api.nvim_create_autocmd("BufEnter", {
pattern = "*",
callback = function() vim.opt.formatoptions:remove({ "c", "r", "o" }) end,
})

vim.opt.shortmess:append("sSwW")
