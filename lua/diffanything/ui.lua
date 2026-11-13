--- Windows and buffers for file diffs and directory diffs.
local scan = require("diffanything.scan")

local M = {}

local ns = vim.api.nvim_create_namespace("diffanything")
local HEADER_LINES = 3

local MARK = { modified = "~", only_a = "-", only_b = "+", same = " " }
local HL = {
  modified = "DiffAnythingModified",
  only_a = "DiffAnythingRemoved",
  only_b = "DiffAnythingAdded",
  same = "DiffAnythingSame",
}

--- Diff two single files side by side in a new tab.
---@param a string
---@param b string
function M.files(a, b)
  vim.cmd.tabnew({ args = { a } })
  vim.cmd.diffsplit({ args = { b }, mods = { vertical = true, split = "belowright" } })
end

---@class diffanything.State
---@field a string
---@field b string
---@field opts diffanything.Config
---@field show_same boolean
---@field entries diffanything.Entry[]
---@field visible diffanything.Entry[]
---@field panel_win integer
---@field panel_buf integer
---@field left_win integer
---@field right_win integer

---@param lines string[]
---@return integer
local function scratch(lines)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].modifiable = false
  return buf
end

--- Buffer for one side of the diff. A missing file shows as an empty buffer so
--- the other side is highlighted as entirely added/removed.
---@param path string
---@return integer
local function side_buffer(path)
  if not vim.uv.fs_stat(path) then
    return scratch({})
  end
  if scan.is_binary(path) then
    local size = vim.uv.fs_stat(path).size
    return scratch({ ("Binary file (%d bytes)"):format(size), path })
  end
  return vim.fn.bufadd(path)
end

---@param st diffanything.State
---@param entry diffanything.Entry
local function open_entry(st, entry)
  if not (vim.api.nvim_win_is_valid(st.left_win) and vim.api.nvim_win_is_valid(st.right_win)) then
    return
  end

  for _, win in ipairs({ st.left_win, st.right_win }) do
    vim.api.nvim_win_call(win, function()
      vim.cmd.diffoff()
    end)
  end

  local sides = {
    { win = st.left_win, path = st.a .. "/" .. entry.path },
    { win = st.right_win, path = st.b .. "/" .. entry.path },
  }
  for _, side in ipairs(sides) do
    vim.api.nvim_win_set_buf(side.win, side_buffer(side.path))
  end
  for _, side in ipairs(sides) do
    vim.api.nvim_win_call(side.win, function()
      vim.cmd.diffthis()
    end)
  end
end

---@param st diffanything.State
local function render(st)
  local lines = { "A  " .. st.a, "B  " .. st.b, "" }
  st.visible = {}
  for _, e in ipairs(st.entries) do
    if st.show_same or e.status ~= "same" then
      st.visible[#st.visible + 1] = e
      lines[#lines + 1] = MARK[e.status] .. " " .. e.path
    end
  end
  if #st.visible == 0 then
    lines[#lines + 1] = "No differences"
  end

  local buf = st.panel_buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = false

  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for row = 0, 1 do
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = #lines[row + 1], hl_group = "Title" })
  end
  for i, e in ipairs(st.visible) do
    local row = HEADER_LINES + i - 1
    vim.api.nvim_buf_set_extmark(buf, ns, row, 0, { end_col = #lines[row + 1], hl_group = HL[e.status] })
  end
end

---@param st diffanything.State
---@return diffanything.Entry?
local function entry_at_cursor(st)
  local row = vim.api.nvim_win_get_cursor(st.panel_win)[1]
  return st.visible[row - HEADER_LINES]
end

---@param st diffanything.State
---@param delta integer
local function step(st, delta)
  local count = #st.visible
  if count == 0 then
    return
  end
  local row = vim.api.nvim_win_get_cursor(st.panel_win)[1]
  local idx = row - HEADER_LINES
  -- Skip identical files when they are shown, so ]f/[f walks the changes.
  for _ = 1, count do
    idx = (idx - 1 + delta) % count + 1
    if st.visible[idx].status ~= "same" then
      break
    end
  end
  vim.api.nvim_win_set_cursor(st.panel_win, { HEADER_LINES + idx, 0 })
  open_entry(st, st.visible[idx])
end

---@param st diffanything.State
local function refresh(st)
  local current = entry_at_cursor(st)
  st.entries = scan.compare(st.a, st.b, st.opts.ignore)
  render(st)
  if current then
    for i, e in ipairs(st.visible) do
      if e.path == current.path then
        vim.api.nvim_win_set_cursor(st.panel_win, { HEADER_LINES + i, 0 })
        return
      end
    end
  end
  local last = vim.api.nvim_buf_line_count(st.panel_buf)
  vim.api.nvim_win_set_cursor(st.panel_win, { math.min(HEADER_LINES + 1, last), 0 })
end

---@param st diffanything.State
local function set_keymaps(st)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = st.panel_buf, nowait = true, silent = true, desc = "DiffAnything: " .. desc })
  end

  map("<CR>", function()
    local e = entry_at_cursor(st)
    if e then
      open_entry(st, e)
      vim.api.nvim_set_current_win(st.right_win)
    end
  end, "open diff and focus it")

  map("o", function()
    local e = entry_at_cursor(st)
    if e then
      open_entry(st, e)
    end
  end, "open diff, stay in list")

  map("]f", function()
    step(st, 1)
  end, "next changed file")
  map("[f", function()
    step(st, -1)
  end, "previous changed file")

  map("i", function()
    st.show_same = not st.show_same
    refresh(st)
  end, "toggle identical files")

  map("r", function()
    refresh(st)
  end, "rescan directories")

  map("q", function()
    if require("diffanything").standalone() then
      vim.cmd.qa()
    else
      vim.cmd.tabclose()
    end
  end, "close tab (quit in standalone mode)")
end

--- Diff two directories recursively in a new tab: a file list on the left,
--- then the two sides of the selected file.
---@param a string absolute directory
---@param b string absolute directory
---@param opts diffanything.Config
function M.dir(a, b, opts)
  ---@type diffanything.State
  local st = {
    a = a,
    b = b,
    opts = opts,
    show_same = opts.show_identical,
    entries = {},
    visible = {},
  }

  vim.cmd.tabnew()
  st.panel_win = vim.api.nvim_get_current_win()
  st.panel_buf = vim.api.nvim_get_current_buf()

  for _, name in ipairs({ "left_win", "right_win" }) do
    vim.cmd("belowright vnew")
    vim.bo.bufhidden = "wipe"
    st[name] = vim.api.nvim_get_current_win()
  end
  vim.cmd.wincmd("=")

  vim.api.nvim_win_set_width(st.panel_win, opts.panel_width)
  vim.wo[st.panel_win].winfixwidth = true
  vim.wo[st.panel_win].number = false
  vim.wo[st.panel_win].relativenumber = false
  vim.wo[st.panel_win].signcolumn = "no"
  vim.wo[st.panel_win].wrap = false
  vim.wo[st.panel_win].cursorline = true

  local buf = st.panel_buf
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "diffanything"

  set_keymaps(st)
  vim.api.nvim_set_current_win(st.panel_win)
  refresh(st)

  local first = st.visible[1]
  if first then
    open_entry(st, first)
  end
end

return M
