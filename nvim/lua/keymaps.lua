local map = vim.keymap.set

map("n", "Y", "y$", { desc = "行末までヤンク" })
map("n", "y<C-a>", "<cmd>%y<cr>", { desc = "ファイル全体のコピー" })
map("i", "<Esc>", "<Space><BS><Esc>")
map("i", "<CR>", "<Space><BS><CR>")
map("", "K", "")
map("n", "<C-A-K>", vim.lsp.buf.hover)

map("n", "<leader>]", function()
  vim.cmd("bnext")
end, { desc = "Next buffer" })

map("n", "<leader>[", function()
  vim.cmd("bprevious")
end, { desc = "Previous buffer" })

map(
  "n",
  "<leader>bd",
  function()
    local is_no_name = vim.bo[0].filetype == nil and true or false
    vim.api.nvim_buf_delete(0, { force = is_no_name })
  end,
  { desc = "Close buffer" }
)
