return {
  preset = "none",
  ["<Tab>"] = { "accept", "fallback" },
  ["<Down>"] = { "select_next", "fallback" },
  ["<Up>"] = { "select_prev", "fallback" },
  ["<C-k>"] = { "show" },
  ["<C-j>"] = { "hide", "fallback" },
}
