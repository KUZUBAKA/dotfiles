return {
	"rachartier/tiny-inline-diagnostic.nvim",
	event = "LspAttach",
	priority = 1000,
	opts = {
		preset = "modern",
		options = {
			show_source = true,
			throttle = 0,
		},
	},
}
