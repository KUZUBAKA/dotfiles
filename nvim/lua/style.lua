local vo = vim.o

vo.number = true
vo.relativenumber = true
vo.cursorline = true
vo.signcolumn = "yes:1"
vo.foldcolumn = "1"
vo.numberwidth = 3
vo.wrap = true
vo.laststatus = 0
vo.showtabline = 0
vo.showmode = false
vo.ruler = false
vo.showcmd = false
vo.cmdheight = 0
vo.hlsearch = false
vim.opt.fillchars = { eob = " " }

-- italic and bold disabled
vim.api.nvim_create_autocmd("ColorScheme", {
 callback = function()
  vim.fn.foreach(vim.api.nvim_get_hl(0, {}), function(hlname, def)
   local disable_def = vim.tbl_deep_extend("force", def,
    { italic = false, bold = false, cterm = { italic = false, bold = false } })
   vim.api.nvim_set_hl(0, hlname, disable_def)
  end)
 end,
})

-- Chars Settings
vim.fn.setcellwidths({
 -- Latin-1 系の曖昧幅記号：± × ÷ ° など
 { 0x00A1,  0x00A1,  2 },
 { 0x00A4,  0x00A4,  2 },
 { 0x00A7,  0x00A8,  2 },
 { 0x00AA,  0x00AA,  2 },
 { 0x00AC,  0x00AC,  2 },
 { 0x00AE,  0x00BA,  2 },
 { 0x00BC,  0x00BF,  2 },
 { 0x00D7,  0x00D7,  2 },
 { 0x00F7,  0x00F7,  2 },

 -- … と ※
 -- { 0x2026,  0x2026,  2 },
 { 0x203B,  0x203B,  2 },

 -- ℃ ℉ № ™ Ω Å など
 { 0x2103,  0x2103,  2 },
 { 0x2109,  0x2109,  2 },
 { 0x2116,  0x2116,  2 },
 { 0x2122,  0x2122,  2 },
 { 0x2126,  0x2126,  2 },
 { 0x212B,  0x212B,  2 },

 -- 矢印：← ↑ → ↓ ⇒ ⇔ など
 { 0x2190,  0x21FF,  2 },

 -- 数学記号：∀ ∂ ∞ ≠ ≤ ≥ など
 { 0x2200,  0x22FF,  2 },

 -- 電源記号など：⏻ ⏼ ⏽ ⏾
 { 0x23FB,  0x23FE,  2 },

 -- 丸数字・囲み文字：① ② ⓪ など
 { 0x2460,  0x24FF,  2 },

 -- 図形記号：■ □ ● ○ ◆ ◇ ★ ☆ など
 -- 罫線 2500-257F は入れない
 { 0x25A0,  0x25FF,  2 },

 -- 天気・警告・装飾・チェック・太い矢印：☀ ♨ ⚠ ✓ ✔ ➡ など
 -- ここに 27A0-27BF も含まれるので、別指定しない
 { 0x2600,  0x27BF,  2 },

 -- 補助矢印・補助数学記号
 -- Braille 2800-28FF は入れない
 { 0x27C0,  0x27FF,  2 },
 { 0x2900,  0x2AFF,  2 },

 -- 追加の矢印・記号
 { 0x2B00,  0x2BFF,  2 },

 -- Nerd Fonts：BMP 私用領域
 { 0xE000,  0xE0AF,  2 },
 { 0xE0C0,  0xF8FF,  2 },

 -- Nerd Fonts：Material Design Icons など
 { 0xF0000, 0xF1FFF, 2 },
})
