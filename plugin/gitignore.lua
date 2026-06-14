--- Plugin commands for gitignore-templates.nvim
--- Loaded automatically by Neovim from plugin/

if vim.g.loaded_gitignore_templates then
  return
end
vim.g.loaded_gitignore_templates = true

vim.api.nvim_create_user_command("Gitignore", function()
  require("gitignore-templates").select_and_apply()
end, {
  desc = "Select and apply a .gitignore template",
})

vim.api.nvim_create_user_command("GitignoreUpdate", function()
  require("gitignore-templates").update_list()
end, {
  desc = "Update the cached .gitignore template list from GitHub",
})

vim.api.nvim_create_user_command("GitignoreClear", function()
  require("gitignore-templates").clear_cache()
end, {
  desc = "Clear all cached .gitignore templates",
})
