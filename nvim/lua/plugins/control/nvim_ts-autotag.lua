return {
	"windwp/nvim-ts-autotag",
	event = "InsertEnter",
	dependencies = { "neovim-treesitter/nvim-treesitter" },
	opts = {
		autotag = {
			enable_rename = true,
			enable_close = true,
			enable_close_on_slash = false,
		}
	},
}
