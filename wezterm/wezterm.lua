local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Style Settigns
config.enable_scroll_bar = false
config.enable_tab_bar = false
config.window_padding = { left = "0px", right = "0px", top = "0px", bottom = "0px" }
config.font_size = 25
config.line_height = 1
config.font = wezterm.font_with_fallback({
 { family = "OUT", weight = 500 },
})

config.background = {
 {
  source = { File = wezterm.home_dir .. "/Wallpapers/東方/12.jpeg" },
  hsb = {
   brightness = 0.10,
   hue = 1.0,
   saturation = 1.0,
  },
  opacity = 1.00,
 },
}

config.cell_widths = {
 -- Latin-1 系の曖昧幅記号：± × ÷ ° など
 { first = 0x00A1, last = 0x00A1, width = 2 },
 { first = 0x00A4, last = 0x00A4, width = 2 },
 { first = 0x00A7, last = 0x00A8, width = 2 },
 { first = 0x00AA, last = 0x00AA, width = 2 },
 { first = 0x00AC, last = 0x00AC, width = 2 },
 { first = 0x00AE, last = 0x00BA, width = 2 },
 { first = 0x00BC, last = 0x00BF, width = 2 },
 { first = 0x00D7, last = 0x00D7, width = 2 },
 { first = 0x00F7, last = 0x00F7, width = 2 },

 -- ※ (… は 1 マスのまま)
 { first = 0x203B, last = 0x203B, width = 2 },

 -- ℃ ℉ № ™ Ω Å
 { first = 0x2103, last = 0x2103, width = 2 },
 { first = 0x2109, last = 0x2109, width = 2 },
 { first = 0x2116, last = 0x2116, width = 2 },
 { first = 0x2122, last = 0x2122, width = 2 },
 { first = 0x2126, last = 0x2126, width = 2 },
 { first = 0x212B, last = 0x212B, width = 2 },

 -- 矢印・数学記号・技術記号：← → ⇒ ∀ ≠ ⌘ ⏻ など
 { first = 0x2190, last = 0x23FF, width = 2 },

 -- 丸数字・囲み文字：① ② ⓪ など
 { first = 0x2460, last = 0x24FF, width = 2 },

 -- 図形・天気・装飾・チェック・補助矢印：■ ● ★ ⚠ ✓ ➡ など
 -- 罫線 2500-259F と点字 2800-28FF は入れない
 { first = 0x25A0, last = 0x27FF, width = 2 },
 { first = 0x2900, last = 0x2BFF, width = 2 },

 -- Nerd Fonts (Powerline の区切り E0B0-E0BF は入れない)
 { first = 0xE000, last = 0xE0AF, width = 2 },
 { first = 0xE0C0, last = 0xF8FF, width = 2 },
 { first = 0xF0000, last = 0xF1FFF, width = 2 },
}

config.custom_block_glyphs = true
config.anti_alias_custom_block_glyphs = true

-- BackEnd
wezterm.log_info("CONFIG FILE = " .. wezterm.config_file)

config.unicode_version = 14
config.freetype_render_target = "HorizontalLcd"
config.allow_square_glyphs_to_overflow_width = "WhenFollowedBySpace"
config.use_resize_increments = true
config.use_fancy_tab_bar = false
config.initial_cols = 100
config.initial_rows = 30
config.window_close_confirmation = 'NeverPrompt'

config.keys = {
 {
  key = "w",
  mods = "CTRL|SHIFT|ALT",
  action = wezterm.action.CloseCurrentPane({ confirm = true }),
 },
 {
  key = " ",
  mods = "CTRL",
  action = wezterm.action.SendKey({ key = " ", mods = "CTRL" }),
 },
 {
  key = " ",
  mods = "SHIFT",
  action = wezterm.action.SendKey({ key = " ", mods = "SHIFT" }),
 },
}

return config
