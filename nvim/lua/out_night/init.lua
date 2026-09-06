local M = {}

local colors = {
 white           = "#e1e5ea",
 gray            = "#1a1c25",
 gray_dark       = "#12131b",
 gray_blue       = "#4a6ca4",
 gray_blue_dark  = "#1e2733",
 gray_blue_light = "#2c3848",

 green           = "#3c7654",
 green_light     = "#98e595",
 green_dark      = "#367369",

 red             = "#f34c4e",
 red_light       = "#ff776e",
 pink            = "#ff8fb2",
 pink_light      = "#ff9dbb",
 pink_dark       = "#ff3e90",
 orange          = "#ffad68",
 orange_dark     = "#d38340",
 yellow          = "#d9cb73",

 blue            = "#3f58d3",
 blue_dark       = "#1d253a",
 blue_light      = "#6881eb",
 blue_very_light = "#adc0ff",
 dodgetblue      = "#9ab3ff",
 skyblue         = "#5edcff",
 skyblue_dark    = "#5c79a0",
 skyblue_light   = "#94aeff",
 cyan            = "#40a0a3",
 nevy            = "#252c4a",
 nevy_dark       = "#171c32",
 magenta         = "#c09cff",
}

local main_highlights = {
 Normal                        = { fg = colors.skyblue_light, bg = colors.gray },
 NormalNC                      = { link = "Normal" },
 CursorLine                    = { bg = "NONE" },
 SnippetTabstopActive = {bg = "NONE"},

 LineNr                        = { fg = colors.blue_light },
 LineNrAbove                   = { link = "LineNr" },
 LineNrBelow                   = { link = "LineNr" },
 CursorLineNr                  = { fg = colors.yellow },

 NormalFloat                   = { fg = colors.skyblue_light, bg = colors.gray_dark },
 FloatTitle                    = { link = "NormalFloat" },
 FloatFooter                   = { link = "NormalFloat" },
 FloatBorder                   = { fg = colors.blue, bg = colors.gray_dark },
 Pmenu                         = { link = "NormalFloat" },

 WinSeparator                  = { fg = colors.blue },
 Folded                        = { bg = "NONE" },

 DiagnosticError               = { fg = colors.red },
 DiagnosticWarn                = { fg = colors.yellow },
 DiagnosticHint                = { fg = colors.skyblue },

 SnacksPickerListCursorLine    = { link = "PmenuSel" },
 SnacksPickerMatch             = { fg = colors.blue },
 SnacksPickerUndoAdded         = { fg = colors.white, bg = "NONE" },
 SnacksPickerUndoRemoved       = { fg = colors.white, bg = "NONE" },
 SnacksPickerUndoSaved         = { fg = "NONE", bg = "NONE" },
 SnacksPickerUndoCurrent       = { fg = colors.white, bg = "NONE" },
 SnacksDashboardIcon           = { fg = colors.skyblue_light },
 SnacksDashboardDesc           = { fg = colors.skyblue_light },
 SnacksDashboardKey            = { fg = colors.red },
 SnacksDashboardHeader         = { fg = colors.yellow },
 SnacksDashboardFooter         = { fg = colors.skyblue_light },

 RainbowDelimiterRed = { fg = colors.red },
 RainbowDelimiterYellow = { fg = colors.yellow },
 RainbowDelimiterBlue = { fg = colors.blue },
 RainbowDelimiterOrange = { fg = colors.orange },
 RainbowDelimiterGreen = { fg = colors.green },
 RainbowDelimiterViolet = { fg = colors.magenta },
 RainbowDelimiterCyan = { fg = colors.cyan },
 RainbowDelimiterCrisp = { fg = colors.pink },
 RainbowDelimiterMist = { fg = colors.gray },

 BlinkCmpLabelMatch            = { fg = colors.blue },
 BlinkCmpMenuBorder            = { fg = colors.blue, bg = colors.gray_dark },
 BlinkCmpMenuSelection         = { link = "PmenuSel" },

 NoiceCmdLinePopup             = { link = "Pmenu" },
 NoiceCmdLinePopupBorder       = { fg = colors.blue, bg = colors.gray_dark },
 NoiceCmdlinePopupBorderSearch = { fg = colors.yellow, bg = colors.gray_dark },

 FlashLabel                    = { fg = colors.yellow },
 FlashMatch                    = { fg = colors.green_light },
 FlashCurrent                  = { link = "FlashMatch" },
 FlashBackdrop                 = { fg = colors.nevy },

 OilDir                        = { fg = colors.skyblue_light },
 LspSignatureActiveParameter = {bg = "NONE"},

 WhichKeyNormal                = { link = "NormalFloat" },
 WhichKeyBorder                = { fg = colors.blue, bg = colors.gray_dark },
}

local text_colors = {
 green_light = "#7ee7ad",
 skyblue = "#4dd3ff",
 skyblue_dark = "#00cdff",
 magenta = "#9877ff",
 yellow = "#e7d777",
 blue = "#57a5ff",
 blue_dark = "#5e92ff",
 dodgetblue = "#73aaff",
 cyan = "#00e7ff",
 nevy = "#6273b7",
 white = "#f2f2f2",
}

local text_highlights = {

 Comment                                = { fg = text_colors.green_light },
 ["@comment"]                           = { link = "Comment" },

 Number                                 = { fg = text_colors.skyblue },
 Float                                  = { fg = text_colors.skyblue },
 ["@number"]                            = { link = "Number" },
 ["@number.float"]                      = { link = "Float" },
 Boolean                                = { fg = colors.skyblue },
 ["@boolean"]                           = { link = "Boolean" },

 Statement                              = { fg = text_colors.magenta },
 Keyword                                = { fg = text_colors.magenta },
 Include                                = { fg = text_colors.magenta },
 ["@keyword"]                           = { link = "Keyword" },
 ["@keyword.coroutine"]                 = { fg = colors.magenta },

 Function                               = { fg = text_colors.yellow },
 ["@function"]                          = { link = "Function" },

 Identifier                             = { fg = colors.blue },
 Variable                               = { fg = text_colors.blue },
 ["@variable"]                          = { link = "Variable" },
 ["@variable.member"]                   = { fg = text_colors.yellow },

 Type                                   = { fg = text_colors.blue_dark},
 ["@property"] = {fg = text_colors.blue_dark},
 Special                                = { fg = text_colors.green_light },

 Tag                                    = { fg = text_colors.yellow },
 ["@tag"]                               = {link = "Tag"},
 ["@tag.attribute.html"]                = { fg = text_colors.blue },

 -- Lua

 ["@constructor.lua"] = {fg = colors.skyblue_light},

 -- Rust

 ["@module.rust"]                       = { fg = text_colors.dodgetblue },
 ["@lsp.type.namespace.rust"]           = { fg = text_colors.dodgetblue },
 ["@lsp.type.attributeBracket.rust"] = {fg = text_colors.nevy},
 ["@lsp.mod.attribute.rust"] = {link = "@lsp.type.attributeBracket.rust"},
 ["@lsp.type.string.rust"] = {fg = text_colors.skyblue},
 ["@lsp.typemod.string.macro.rust"] = {fg = text_colors.skyblue},
 ["@lsp.typemod.string.procMacro"] = {fg = text_colors.skyblue},

 -- Markdown

 ["@markup.heading.1"]                  = { fg = text_colors.blue_dark },
 ["@markup.heading.2"]                  = { fg = text_colors.blue },
 ["@markup.heading.3"]                  = { fg = text_colors.skyblue_dark },
 ["@markup.heading.4"]                  = { fg = text_colors.skyblue },
 ["@markup.heading.5"]                  = { fg = text_colors.cyan },
 ["@markup.heading.6"]                  = { fg = text_colors.magenta },
 ["@markup.strong"]                     = { fg = colors.red_light },
 ["@markup.italic"]                     = { fg = text_colors.yellow },
 ["@markup.link.label.markdown_inline"] = { fg = text_colors.nevy },
 ["@markup.link.bracket"]               = { link = "@markup.link.label.markdown_inline" },
 ["@markup.list"]                       = { fg = text_colors.dodgetblue },
 ["@punctuation.special.markdown"]      = { fg = colors.orange_dark },
 ["@markup.raw.block"]                  = { fg = text_colors.light_green },
 ["@markup.raw.markdown_inline"]        = { fg = text_colors.light_green },
}

local no_transparent_highlights = {
 Visual           = { bg = colors.blue_light },
 VisualNOS        = { link = "Visual" },
 PmenuSel         = { bg = colors.gray },

 WinBar           = { fg = colors.skyblue_light, bg = "NONE" },
 WinBarNC         = { fg = colors.skyblue_light, bg = "NONE" },
 WinBarFP         = { fg = colors.skyblue_light, bg = colors.blue },
 WinBarFPSep      = { fg = colors.blue, bg = "NONE" },

 -- TabLine          = { fg = colors.skyblue_light, bg = "NONE" },
 -- TabLineSel       = { fg = colors.skyblue_light, bg = colors.nevy },
 -- HlTabActiveSep   = { fg = colors.nevy, bg = "NONE" },
 -- HlTabInActiveSep = { fg = "NONE", bg = colors.nevy },

 StatusLine       = { bg = "NONE" },

 HlModeNormal     = { fg = colors.skyblue_light, bg = colors.blue_dark },
 HlModeInsert     = { fg = colors.skyblue_light, bg = colors.green_dark },
 HlModeVisual     = { fg = colors.skyblue_light, bg = colors.magenta },
 HlModeReplace    = { fg = colors.skyblue_light, bg = colors.red },
 HlModeCmd        = { fg = colors.skyblue_light, bg = colors.orange_dark },
 HlSepNormalR     = { fg = colors.blue_dark, bg = colors.nevy },
 HlSepInsertR     = { fg = colors.green_dark, bg = colors.nevy },
 HlSepVisualR     = { fg = colors.magenta, bg = colors.nevy },
 HlSepReplaceR    = { fg = colors.red, bg = colors.nevy },
 HlSepCmdR        = { fg = colors.orange_dark, bg = colors.nevy },

 HlFilePath       = { fg = colors.white, bg = colors.nevy },
 HlFileType       = { fg = colors.white, bg = colors.nevy },
 HlSepFPR         = { fg = colors.skyblue_dark, bg = colors.nevy },
 HlSepFTR         = { fg = colors.nevy, bg = "NONE" },

 HlDiagnostics    = { fg = colors.skyblue_light, bg = colors.blue_dark },
 HlSelChars       = { fg = colors.skyblue_light, bg = colors.nevy },
 HlChars          = { fg = colors.skyblue_light, bg = colors.nevy },
 HlCursorPos      = { fg = colors.skyblue_light, bg = colors.nevy },
 HlDate           = { fg = colors.skyblue_light, bg = colors.green },
 HlDiagnosticsSep = { fg = colors.blue_dark, bg = colors.nevy },
 HlSelCharsSep    = { fg = colors.skyblue_dark, bg = colors.nevy },
 HlCharsSep       = { fg = colors.nevy, bg = colors.nevy },
 HlCursorPosSep   = { fg = colors.nevy, bg = "NONE" },
 HlSepDate        = { fg = colors.green, bg = "NONE" },
}

local disabled_decorations = {
 underline = false,
 bold = false,
 italic = false,
}

function M.setup(opts)
 vim.cmd("highlight clear")
 vim.cmd("syntax reset")

 if opts ~= nil and opts then
  for _, h_opts in pairs(main_highlights) do
   h_opts.bg = "NONE"
  end
 end

 local hl = vim.tbl_extend("force", vim.api.nvim_get_hl(0, { link = false }), main_highlights)
 hl = vim.tbl_extend("force", hl, no_transparent_highlights)
 hl = vim.tbl_extend("force", hl, text_highlights)

 for group, h_opts in pairs(hl) do
  vim.api.nvim_set_hl(0, group, vim.tbl_extend("force", h_opts, disabled_decorations))
 end
end

return M
