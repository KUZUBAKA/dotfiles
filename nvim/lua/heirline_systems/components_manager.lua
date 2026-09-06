local M = {}

M.current_mode = { require("heirline_systems.components.current_mode") }
M.file_path = { require("heirline_systems.components.file_path") }
M.file_devicon = { require("heirline_systems.components.file_info").devicon }
M.file_type = { require("heirline_systems.components.file_info").filetype }
M.file_encoding = { require("heirline_systems.components.file_info").encoding }
M.date = { require("heirline_systems.components.clock").date }
M.diagnostics = { require("heirline_systems.components.diagnostics") }
M.chars = { require("heirline_systems.components.chars_count").chars }
M.sel_chars = require("heirline_systems.components.chars_count").sel_chars
M.cursor_pos = require("heirline_systems.components.cursor_position")

return M
