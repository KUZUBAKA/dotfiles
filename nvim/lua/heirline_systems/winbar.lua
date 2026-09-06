local sep_r = require("heirline_systems.separators").right_filled

local function is_fp() return vim.api.nvim_buf_get_name(0) ~= "" end

return {
	hl = "WinBar",
	{ hl = "WinBarFP", provider = " ", condition = function() return is_fp() end, },
	{
		hl = "WinBarFP",
		update = { "BufEnter" },
		condition = function() return is_fp() end,
		init = function(self) self.path = vim.api.nvim_buf_get_name(0) end,
		provider = function(self)
			local normalized = self.path:gsub("\\", "/")
			local h4 = vim.fn.fnamemodify(normalized, ":h:h:h:h:t")
			local h3 = vim.fn.fnamemodify(normalized, ":h:h:h:t")
			local h2 = vim.fn.fnamemodify(normalized, ":h:h:t")
			local h1 = vim.fn.fnamemodify(normalized, ":h:t")
			local t = vim.fn.fnamemodify(normalized, ":t")

			if h4 then return h4 .. "/" .. h3 .. "/" .. h2 .. "/" .. h1 .. "/" .. t end
			if h3 then return h3 .. "/" .. h2 .. "/" .. h1 .. "/" .. t end
			if h2 then return h2 .. "/" .. h1 .. "/" .. t end
			if h1 then return h1 .. "/" .. t end
			return t
		end
	},
	{ hl = "WinBarFP", provider = " ", condition = is_fp },
	{
		update = { "BufEnter" },
		condition = function() return is_fp() end,
		hl = "WinBarFPSep",
		provider = sep_r .. " ",
	},
}
