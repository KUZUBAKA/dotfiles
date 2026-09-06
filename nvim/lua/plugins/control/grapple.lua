local function short_path(path)
  local norm = path:gsub("\\", "/")
  local t = vim.fn.fnamemodify(norm, ":t")
  local h1 = vim.fn.fnamemodify(norm, ":h:t")
  local h2 = vim.fn.fnamemodify(norm, ":h:h:t")
  local ok = function(s) return s ~= "" and s ~= "." and not s:match("^%a:$") end
  if ok(h2) then
    return h2 .. "/" .. h1 .. "/" .. t
  elseif ok(h1) then
    return h1 .. "/" .. t
  else
    return t
  end
end

local function get_prefix(path)
  if vim.uv.os_uname().sysname == "Windows_NT" then
    return path:match("^(%a:)") or "/"
  end
  return "/"
end

return {
  "cbochs/grapple.nvim",
  event = "VeryLazy",
  dependencies = { "nvim-tree/nvim-web-devicons", },
  init = function()
    vim.api.nvim_create_autocmd("FileType", {
      pattern = "grapple",
      callback = function()
        vim.opt_local.number = false
        vim.opt_local.relativenumber = false
      end
    })
  end,
  keys = {
    { "<leader>a", function() require("grapple").tag() end, desc = "Grapple Tag" },
    {
      "<leader>e",
      function()
        require("grapple").toggle_tags()
      end,
      desc = "Grapple Toggle Tags"
    },
  },
  opts = {
    scope = "global",
    style = "drive_style",
    styles = {
      drive_style = function(entity, _)
        local prefix = get_prefix(entity.tag.path)
        local dir = short_path(entity.tag.path)
        return { display = "[" .. prefix .. dir .. "]", marks = {} }
      end,
    }
  },
}
