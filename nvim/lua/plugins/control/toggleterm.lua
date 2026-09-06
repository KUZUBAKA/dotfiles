return {
	"akinsho/toggleterm.nvim",
	keys = {
		{
			"<leader>tt",
			function()
				require("toggleterm").toggle()
			end,
			desc = "Toggle term",
		},
		{
			"<leader>tk",
			function()
				local job_id = vim.b.terminal_job_id
				if not job_id then return end
				if job_id then
					vim.fn.chansend(job_id, "\3")
				end

				local shell_pid = vim.fn.jobpid(job_id)
				vim.fn.jobstart({ "taskkill", "/F", "/T", "/PID", tostring(shell_pid) })
			end,
			desc = "Task kill",
		},
	},
	version = "*",
	opts = {
		insert_mappings = false,
		terminal_mappings = false,
		start_in_insert = true,
		close_on_exit = true,
		direction = "float",
		on_open = function(term)
			vim.api.nvim_buf_set_keymap(term.bufnr, "t", "<Esc>", "<c-\\><c-n>", { noremap = true, silent = true })
		end,
	}
}
