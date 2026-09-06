return function()
 vim.lsp.config("rust_analyzer", {
  settings = {
   ["rust-analyzer"] = {
    inlayHints = {
     typeHints = { enable = true },
     parameterHints = { enable = false },
     chainingHints = { enable = true },
    },
    procMacro = {
     enable = true,
     attributes = { enable = true },
    },
    diagnostics = {
     enable = true,
    },
    completion = {
     autoimport = { enable = false },
     postfix = { enable = true },
     addMovesToClosureSnippets = true,
    },
    cargo = {
     allTargets = false,
     targetDir = true,
     buildScripts = { enable = true },
     features = "all",
    },
    checkOnSave = true,
    check = {
     allTargets = false,
     ignore = {
      "unused_imports",
      "dead_code",
      "unused_variables",
      "unused_mut",
     },
    },
    -- lspMux = {
    --  version = "1",
    --  method = "connect",
    --  server = "rust-analyzer",
    -- },
   },
  },
 })
end
