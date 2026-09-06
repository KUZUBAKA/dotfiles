return {
	"ysmb-wtsg/in-and-out.nvim",
	event = "InsertEnter",
	keys = {
		{
			"<S-Tab>",
			function()
				local col = vim.api.nvim_win_get_cursor(vim.api.nvim_get_current_win())[2]
				local next = vim.api.nvim_get_current_line():sub(col + 1, col + 1)

				if vim.tbl_contains({ ")", "]", "}", '"', "'", "`" }, next) then
					require("in-and-out").in_and_out()
				else
					vim.api.nvim_feedkeys("\t", "n", false)
				end
			end,
			mode = "i",
			desc = "In and Out",
		},
	},
	opts = {},
}
