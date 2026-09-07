local wezterm = require("wezterm")
local config = wezterm.config_builder()

-- Style Settigns
config.enable_scroll_bar = false
config.enable_tab_bar = false
config.window_padding = { left = "0px", right = "0px", top = "0px", bottom = "0px" }
config.font_size = 14
config.line_height = 1
config.font = wezterm.font_with_fallback({
 { family = "OUT", weight = "Regular" },
})

config.background = {
 {
  source = { File = wezterm.home_dir .. "/Wallpapers/東方/6.png" },
  hsb = {
   brightness = 0.04,
   hue = 1.0,
   saturation = 1.0,
  },
  opacity = 1.00,
 },
}

config.custom_block_glyphs = true
config.anti_alias_custom_block_glyphs = true

config.cell_widths = {
 -- 句読点系の曖昧幅記号：‐ - ‒ – — ― ‖ ‘ ’ “ ” † ‡ • … ‰ ′ ″ ※ ‼ など
 -- { first = 0x2010, last = 0x2027, width = 2 },
 -- { first = 0x2030, last = 0x205E, width = 2 },

 -- 矢印・数学記号：← → ⇒ ⇔ ∀ ∂ ∞ ≠ ≤ ≥ など
 { first = 0x2190, last = 0x22FF, width = 2 },

 -- 技術記号・電源記号：⌘ ⌥ ⏻ ⏼ ⏽ ⏾ など
 { first = 0x2300, last = 0x23FF, width = 2 },

 -- 丸数字・囲み文字：① ② ⓪ など
 { first = 0x2460, last = 0x24FF, width = 2 },

 -- 図形・天気・装飾記号：■ □ ● ○ ◆ ◇ ★ ☆ ♨ ⚠ ✓ ✔ ➡ など
 -- 2500-257F の罫線は含めない
 { first = 0x25A0, last = 0x27BF, width = 2 },
}

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
