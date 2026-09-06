return function()
	vim.lsp.config("gdscript", {
		cmd = vim.lsp.rpc.connect("127.0.0.1", 6005),
		filetypes = { "gd", "gdscript", "gdscript3", "gdscript4" },
		root_markers = { "project.godot", ".git" },
		handlers = {
			["window/showMessage"] = function(err, result, ctx)
				if result and result.message and result.message:find("might not work") then return end
				return vim.lsp.handlers["window/showMessage"](err, result, ctx)
			end,
		},
	})

	local cwd = vim.fn.getcwd()
	if vim.uv.fs_stat(cwd .. "/project.godot") then
		local server_addr = "127.0.0.1:55432"
		local already_running = false
		for _, addr in ipairs(vim.fn.serverlist()) do
			if addr == server_addr then
				already_running = true
				break
			end
		end
		if not already_running then vim.fn.serverstart(server_addr) end
	end
end
