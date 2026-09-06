return {
	"johmsalas/text-case.nvim",
	event = "VeryLazy",
	keys = {
		{ "<leader>tc", function() require("textcase").current_word("to_camel_case") end,    desc = "To camelCase" },
		{ "<leader>ts", function() require("textcase").current_word("to_snake_case") end,    desc = "To snake_case" },
		{ "<leader>tu", function() require("textcase").current_word("to_constant_case") end, desc = "To CONSTANT_CASE" },
	},
	opts = {},
}
