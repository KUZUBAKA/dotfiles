return {
"folke/snacks.nvim",
priority = 1000,
lazy = false,
keys = {
{ "<leader>ff",   function() require("snacks.picker").files() end,                                      desc = "Find files" },
{ "<leader>fg",   function() require("snacks.picker").grep() end,                                       desc = "Live grep" },
{ "<leader>faf",  function() require("snacks.picker").files({ hidden = true, ignored = true }) end,     desc = "Find files" },
{ "<leader>fag",  function() require("snacks.picker").grep({ hidden = true, ignored = true }) end,      desc = "Live grep" },
{ "<leader>fb",   function() require("snacks.picker").buffers() end,                                    desc = "Find buffers" },
{ "<leader>fhh",  function() require("snacks.picker").help() end,                                       desc = "Find help" },
{ "<leader>fhla", function() require("snacks").picker.highlights() end,                                 desc = "Show highlights" },
{ "<leader>fhll", function() require("snacks").picker.highlights({ pattern = "hl_group:^" }) end,       desc = "Show limit highlights" },
{ "<leader>fhls", function() require("snacks").picker.highlights({ pattern = "hl_group:^Snacks" }) end, desc = "Show snacks highlights" },
{ "<leader>fe",   function() require("snacks").notifier.show_history() end,                             desc = "Show notifier" },
{ "<leader>fs",   function() require("snacks").scratch() end,                                           desc = "Show scratch" },
{ "<leader>cR",   function() require("snacks").rename.rename_file() end,                                desc = "File rename" },
{ "<leader>Z",    function() require("snacks").zen() end,                                               desc = "Zen mode enter" },
-- { "<leader>tt",   function() require("snacks").terminal() end,                                          desc = "Terminal open" },
},
---@type snacks.Config
opts = {
dashboard = {
enabled = true,
sections = {
{ section = "header" },
{ section = "keys",   gap = 1 },
{ section = "startup" },
},
preset = {
header = [[
_   _                 _
| \ | | ___  _____   _(_)_ __ ___
|  \| |/ _ \/ _ \ \ / / | '_ ` _ \
| |\  |  __/ (_) \ V /| | | | | | |
|_| \_|\___|\___/ \_/ |_|_| |_| |_|]],
keys = {
{ icon = "󰝒", key = "n", desc = "New File", action = "<cmd>ene<cr>" },
{ icon = "󰍉", key = "f", desc = "Find File", action = function() require("snacks.picker").files() end },
{ icon = "󰺮", key = "g", desc = "Live Grep", action = function() require("snacks.picker").grep() end },
{ icon = "󰝰", key = "o", desc = "Open Oil", action = "<cmd>Oil<cr>" },
{ icon = "󰒲", key = "l", desc = "Lazy", action = "<cmd>Lazy<cr>" },
{ icon = "󱌣", key = "m", desc = "Mason", action = "<cmd>Mason<cr>" },
{ icon = "󰅚", key = "q", desc = "Quit", action = "<cmd>qa<cr>" },
},
},
},
scratch = {
enabled = true,
win = {
width = 0.8,
height = 0.7,
wo = {
winbar = "",
},
border = true,
},
ft = "markdown",
},
picker = {
enabled = true,
sources = {
files = { follow = true },
grep  = { follow = true },
},
exclude = { "target", ".git" },
},
notifier = {
enabled = true,
style = "compact",
filter = function (notif)
return not notif.msg:find("request handler");
end
},
input = { enabled = true },
scroll = { enabled = true },
bufdelete = { enabled = true },
rename = { enabled = true },
zen = { enabled = true },
-- terminal = {
-- 	enabled = true,
-- 	start_insert = true,
-- 	auto_close = true,
-- 	win = {
-- 		position = "float",
-- 		border = "rounded",
-- 	},
-- },
},
}
