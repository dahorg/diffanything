if vim.g.loaded_diffanything then
  return
end
vim.g.loaded_diffanything = true

vim.api.nvim_set_hl(0, "DiffAnythingModified", { link = "Changed", default = true })
vim.api.nvim_set_hl(0, "DiffAnythingAdded", { link = "Added", default = true })
vim.api.nvim_set_hl(0, "DiffAnythingRemoved", { link = "Removed", default = true })
vim.api.nvim_set_hl(0, "DiffAnythingSame", { link = "Comment", default = true })

vim.api.nvim_create_user_command("DiffAnything", function(cmd)
  local n = #cmd.fargs
  if n == 0 then
    require("diffanything").start()
  elseif n == 1 then
    require("diffanything").start(cmd.fargs[1])
  elseif n == 2 then
    require("diffanything").diff(cmd.fargs[1], cmd.fargs[2])
  else
    vim.notify("Usage: :DiffAnything [path-a] [path-b]", vim.log.levels.ERROR)
  end
end, {
  nargs = "*",
  complete = "file",
  desc = "Diff two files, or two directories recursively (prompts for missing paths)",
})
