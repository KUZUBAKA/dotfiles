return function()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  local target_col = math.max(0, col - 1)

  local ok, node = pcall(vim.treesitter.get_node, { bufnr = 0, pos = { row - 1, target_col } })
  if ok and node then
    if vim.tbl_contains({ "comment", "comment_content", "line_comment", "block_comment" }, node:type()) then
      return true
    end
  end

  local ok2, captures = pcall(vim.treesitter.get_captures_at_cursor, 0)
  if ok2 and captures then
    for _, cap in ipairs(captures) do
      if cap:match("comment") then return true end
    end
  end

  return false
end
