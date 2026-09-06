return {
	"mrjones2014/smart-splits.nvim",
	opts = {
		ignored_buftypes = { "nofile", "quickfix", "prompt" },
	},
	keys = {
		{ "<C-Left>",  function() require("smart-splits").resize_left() end,  desc = "Window: Resize Left" },
		{ "<C-Down>",  function() require("smart-splits").resize_down() end,  desc = "Window: Resize Down" },
		{ "<C-Up>",    function() require("smart-splits").resize_up() end,    desc = "Window: Resize Up" },
		{ "<C-Right>", function() require("smart-splits").resize_right() end, desc = "Window: Resize Right" },
	},
}
