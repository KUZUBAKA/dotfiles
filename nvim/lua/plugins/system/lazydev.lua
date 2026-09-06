return {
	"folke/lazydev.nvim",
	dependencies = {
		"DrKJeff16/wezterm-types",
	},
	ft = "lua",
	opts = {
		library = {
			"lazy.nvim",
			vim.fn.stdpath("config") .. "/lua/types",
			{ path = "wezterm-types", mods = { "wezterm" } },
		},
	},
}
