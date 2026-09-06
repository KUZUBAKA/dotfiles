return {
	"brianhuster/live-preview.nvim",
	cmd = "LivePreview",
	keys = {
		{ "<leader>lp", "<cmd>LivePreview start<cr>", desc = "Live Preview Start" },
		{ "<leader>ls", "<cmd>LivePreview stop<cr>", desc = "Live Preview Stop" },
	},
	opts = {
		port = 5500,
		browser = "default",
	},
}
