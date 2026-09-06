return {
	"stevearc/overseer.nvim",
	event = "VeryLazy",
	keys = {
		{ "<leader>ot", "<cmd>OverseerToggle<cr>", desc = "Overseer Toggle" },
		{ "<leader>or", "<cmd>OverseerRun<cr>", desc = "Overseer Run" },
		{ "<leader>ob", "<cmd>OverseerBuild<cr>", desc = "Overseer Build" },
	},
	opts = {
		tasklist = {
			directionv = "bottom",
			min_height = 10,
			max_height = 15,
		},
	},
}
