return function()
	vim.lsp.config("lua_ls", {
		settings = {
			Lua = {
				runtime = { version = "LuaJIT" },
				diagnostics = { globals = { "vim", "require", "describe", "it", "table" } },
			},
		},
	})
end
