return {
	"folke/trouble.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = { "Trouble" },
	keys = {
		{ "<leader>xx", "<cmd>Trouble diagnostics toggle focus=true<cr>",              desc = "Diagnostics (Trouble)" },
		{ "<leader>xb", "<cmd>Trouble diagnostics toggle filter.buf=0 focus=true<cr>", desc = "Buffer Diagnostics (Trouble)" },
		{ "<leader>xs", "<cmd>Trouble symbols toggle<cr>",                             desc = "Symbols (Trouble)" },
		{ "<leader>xq", "<cmd>Trouble qflist toggle<cr>",                              desc = "Quickfix (Trouble)" },
	},
	opts = {
		open_no_results = true,
		win = { type = "float", },
	},
}
