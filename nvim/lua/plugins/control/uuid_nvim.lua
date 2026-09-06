return {
	'TrevorS/uuid-nvim',
	lazy = true,
	opts = { case = 'lower', },
	keys = { { "<C-u>", function() require("uuid-nvim").insert_v4() end, desc = "Insert uuid" } },
}
