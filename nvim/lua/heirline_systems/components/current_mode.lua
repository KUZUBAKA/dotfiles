local sep = require("heirline_systems.separators")

local result = {
	static = {
		mode_names = {
			n = "NORMAL",
			i = "INSERT",
			v = "VISUAL",
			V = "V-LINE",
			["\22"] = "V-BLOCK",
			c = "COMMAND",
			t = "TERMINAL",
			R = "REPLACE",
			s = "SELECT",
		},

		mode_hl = {
			n = "HlModeNormal",
			i = "HlModeInsert",
			v = "HlModeVisual",
			V = "HlModeVisual",
			["\22"] = "HlModeVisual",
			c = "HlModeCmd",
			t = "HlModeNormal",
			R = "HlModeReplace",
			s = "HlModeVisual",
		},

		sep_hl = {
			n = "HlSepNormalR",
			i = "HlSepInsertR",
			v = "HlSepVisualR",
			V = "HlSepVisualR",
			["\22"] = "HlSepVisualR",
			c = "HlSepCmdR",
			t = "HlSepNormalR",
			R = "HlSepReplaceR",
			s = "HlSepVisualR",
		}
	},
	update = { "ModeChanged", },
	init = function(self) self.mode = vim.fn.mode() end,

	{
		hl = function(self) return self.mode_hl[self.mode] or "HlModeNormal" end,
		provider = function(self) return " " .. (self.mode_names[self.mode] or self.mode) .. " " end,
	},

	{
		hl = function(self) return self.sep_hl[self.mode] or "HlModeNormalR" end,
		provider = sep.right_filled,
	}
}

return result
