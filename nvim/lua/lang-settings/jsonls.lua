return function()
  local schemas = vim.tbl_filter(function(schema)
    if not schema.fileMatch then
      return true
    end

    for _, pattern in ipairs(schema.fileMatch) do
      if pattern == "manifest.json" or pattern == "/manifest.json" then
        return false
      end
    end

    return true
  end, require("schemastore").json.schemas())

  local is_addon = require("lang-settings.minecraft").has_manifest()

  if is_addon then
    local bc_schemas = require("lang-settings.minecraft").get_blockception_schemas()
    vim.list_extend(schemas, bc_schemas)
  end

  vim.lsp.config("jsonls", {
    settings = {
      json = {
        schemas = schemas,
        validate = { enable = true },
        format = { enable = false },
      },
    },
  })
end
