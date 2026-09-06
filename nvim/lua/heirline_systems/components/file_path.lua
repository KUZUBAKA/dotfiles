local result = {
  update = { "BufEnter" },
  provider = function()
    local path = vim.api.nvim_buf_get_name(0)
    local norm = path:gsub("\\", "/")
    if norm == "" then return " [No Name] " end
    local filename = vim.fn.fnamemodify(norm, ":t")
    -- local parent_dir = vim.fn.fnamemodify(norm, ":h:t")
    -- return parent_dir .. "/" .. filename
    return " " .. filename .. " "
  end,
}

return result
