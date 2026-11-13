--- Small floating file/directory browser used to choose what to diff.
local uv = vim.uv or vim.loop

local M = {}

local ns = vim.api.nvim_create_namespace("diffanything-picker")

---@param dir string
---@param hidden boolean
---@return {name: string, type: string}[]
local function list(dir, hidden)
  local items = {}
  for name, kind in vim.fs.dir(dir) do
    if kind == "link" then
      local st = uv.fs_stat(dir .. "/" .. name)
      kind = st and st.type or kind
    end
    if hidden or name:sub(1, 1) ~= "." then
      items[#items + 1] = { name = name, type = kind }
    end
  end
  table.sort(items, function(x, y)
    local xd, yd = x.type == "directory", y.type == "directory"
    if xd ~= yd then
      return xd
    end
    return x.name:lower() < y.name:lower()
  end)
  return items
end

---@class diffanything.PickOpts
---@field title string
---@field start string absolute directory to start in
---@field on_select fun(path: string)
---@field on_cancel? fun()

---@param opts diffanything.PickOpts
function M.pick(opts)
  local resolve = require("diffanything").resolve
  local state = { dir = opts.start, hidden = false, items = {} }

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"

  local width = math.min(90, vim.o.columns - 4)
  local height = math.min(30, vim.o.lines - 6)
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.floor((vim.o.lines - height) / 2) - 1,
    col = math.floor((vim.o.columns - width) / 2),
    style = "minimal",
    border = "rounded",
    title = " " .. opts.title .. " ",
    title_pos = "center",
    footer = " <CR> open/select  <Space> select  . this dir  - up  H hidden  e type path  q cancel ",
    footer_pos = "center",
  })
  vim.wo[win].cursorline = true

  local function render()
    state.items = list(state.dir, state.hidden)
    local lines = { state.dir .. "/" }
    for _, item in ipairs(state.items) do
      lines[#lines + 1] = item.name .. (item.type == "directory" and "/" or "")
    end
    if #state.items == 0 then
      lines[#lines + 1] = "(empty)"
    end
    vim.bo[buf].modifiable = true
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
    vim.bo[buf].modifiable = false

    vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, ns, 0, 0, { end_col = #lines[1], hl_group = "Title" })
    for i, item in ipairs(state.items) do
      if item.type == "directory" then
        vim.api.nvim_buf_set_extmark(buf, ns, i, 0, { end_col = #lines[i + 1], hl_group = "Directory" })
      end
    end
    vim.api.nvim_win_set_cursor(win, { math.min(2, #lines), 0 })
  end

  local function close()
    if vim.api.nvim_win_is_valid(win) then
      vim.api.nvim_win_close(win, true)
    end
  end

  local function finish(path)
    close()
    vim.schedule(function()
      opts.on_select(path)
    end)
  end

  local function cancel()
    close()
    if opts.on_cancel then
      vim.schedule(opts.on_cancel)
    end
  end

  ---@return {name: string, type: string}?, string?
  local function under_cursor()
    local item = state.items[vim.api.nvim_win_get_cursor(win)[1] - 1]
    return item, item and (state.dir .. "/" .. item.name) or nil
  end

  local function enter()
    local item, path = under_cursor()
    if not item then
      return
    end
    if item.type == "directory" then
      state.dir = path
      render()
    else
      finish(path)
    end
  end

  local function up()
    local parent = vim.fs.dirname(state.dir)
    if parent and parent ~= state.dir then
      local came_from = vim.fs.basename(state.dir)
      state.dir = parent
      render()
      for i, item in ipairs(state.items) do
        if item.name == came_from then
          vim.api.nvim_win_set_cursor(win, { i + 1, 0 })
          break
        end
      end
    end
  end

  local function map(lhs, fn)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true })
  end

  map("<CR>", enter)
  map("l", enter)
  map("-", up)
  map("h", up)
  map("<BS>", up)
  map("<Space>", function()
    local _, path = under_cursor()
    if path then
      finish(path)
    end
  end)
  map(".", function()
    finish(state.dir)
  end)
  map("H", function()
    state.hidden = not state.hidden
    render()
  end)
  map("e", function()
    vim.ui.input({ prompt = "Path: ", default = state.dir .. "/", completion = "file" }, function(input)
      if not input or input == "" then
        return
      end
      local path = resolve(input)
      if uv.fs_stat(path) then
        finish(path)
      else
        vim.notify("DiffAnything: no such file or directory: " .. path, vim.log.levels.ERROR)
      end
    end)
  end)
  map("q", cancel)
  map("<Esc>", cancel)

  render()
end

return M
