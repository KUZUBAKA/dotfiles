return function()
	vim.lsp.config("yamlls", {
		settings = {
			yaml = {
				schemaStore = { enable = false, url = "" },
				schemas = require("schemastore").yaml.schemas(),
			},
		},
	})
end
