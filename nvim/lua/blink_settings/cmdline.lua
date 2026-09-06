return {
  enabled = true,
  keymap = { preset = "cmdline" },
  completion = { menu = { auto_show = true } },
  sources = function()
    local type = vim.fn.getcmdtype()
    if type == "/" or type == "?" then return {} end
    if type == ":" or type == "@" then return { "cmdline", "buffer" } end
    return {}
  end,
}
