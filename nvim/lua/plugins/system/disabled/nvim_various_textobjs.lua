return {
	"chrisgrieser/nvim-various-textobjs",
	event = "VeryLazy",
	opts = {
		keymaps = {
			useDefaults = true
		}
	},
	keys = {
		{ "is", function() require("various-textobjs").subword("outer") end, mode = { "o", "x" } },
	},
}
