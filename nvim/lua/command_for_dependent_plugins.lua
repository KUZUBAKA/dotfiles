vim.api.nvim_create_autocmd("User", {
  pattern = "OilActionsPost",
  callback = function(event)
    local actions = event.data and event.data.actions
    if not actions then return end
    for _, action in ipairs(actions) do
      if action.type == "move" then
        require("snacks").rename.on_rename_file(action.src_url, action.dest_url)
      end
    end
  end,
})

vim.api.nvim_create_user_command("PathToggle", function()
  if vim.g.path_src == "cwd" then
    vim.g.path_src = "file"
    vim.notify("パス補完起点: 現ファイル", vim.log.levels.INFO)
  else
    vim.g.path_src = "cwd"
    vim.notify("パス補完起点: プロジェクトルート", vim.log.levels.INFO)
  end
end, { desc = "Toggle path comletion soruce bitween cwd and current file" })
