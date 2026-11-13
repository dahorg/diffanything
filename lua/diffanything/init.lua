local M = {}

---@class diffanything.Config
---@field ignore string[] basenames skipped during directory comparison
---@field show_identical boolean list identical files in the directory view
---@field panel_width integer width of the file list

---@type diffanything.Config
M.config = {
  ignore = { ".git", "node_modules" },
  show_identical = false,
  panel_width = 40,
}

---@param opts? diffanything.Config
function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

---@param path string
---@return string
local function resolve(path)
  local abs = vim.fs.normalize(vim.fn.fnamemodify(path, ":p"))
  return (abs:gsub("(.)/+$", "%1"))
end

M.resolve = resolve

--- True when started through the `diffanything` launcher script, where closing
--- the view should quit Neovim.
---@return boolean
function M.standalone()
  return vim.g.diffanything_standalone == 1
end

local function quit_if_standalone()
  if M.standalone() then
    vim.cmd.qa()
  end
end

--- Interactively choose what to diff. If `a` is given only B is prompted for.
---@param a? string
function M.start(a)
  local picker = require("diffanything.picker")

  local function pick_b(path_a)
    local kind = vim.uv.fs_stat(path_a).type
    picker.pick({
      title = ("Select B to compare with %s (%s)"):format(vim.fs.basename(path_a), kind),
      start = vim.fs.dirname(path_a),
      on_select = function(path_b)
        M.diff(path_a, path_b)
      end,
      on_cancel = quit_if_standalone,
    })
  end

  if a then
    a = resolve(a)
    if not vim.uv.fs_stat(a) then
      return vim.notify("DiffAnything: no such file or directory: " .. a, vim.log.levels.ERROR)
    end
    return pick_b(a)
  end

  picker.pick({
    title = "Select A (file or directory)",
    start = resolve(vim.uv.cwd() or "."),
    on_select = pick_b,
    on_cancel = quit_if_standalone,
  })
end

--- Entry point for the launcher script: reads DIFFANYTHING_A / DIFFANYTHING_B.
function M.cli()
  local a, b = vim.env.DIFFANYTHING_A, vim.env.DIFFANYTHING_B
  if a and a ~= "" and b and b ~= "" then
    M.diff(a, b)
  else
    M.start(a ~= "" and a or nil)
  end
end

--- Diff two files, or two directories recursively.
---@param a string
---@param b string
function M.diff(a, b)
  a, b = resolve(a), resolve(b)

  local sa, sb = vim.uv.fs_stat(a), vim.uv.fs_stat(b)
  if not sa then
    return vim.notify("DiffAnything: no such file or directory: " .. a, vim.log.levels.ERROR)
  end
  if not sb then
    return vim.notify("DiffAnything: no such file or directory: " .. b, vim.log.levels.ERROR)
  end
  if sa.type ~= sb.type then
    return vim.notify("DiffAnything: cannot compare a " .. sa.type .. " with a " .. sb.type, vim.log.levels.ERROR)
  end

  local ui = require("diffanything.ui")
  if sa.type == "directory" then
    ui.dir(a, b, M.config)
  else
    ui.files(a, b)
  end
end

return M
