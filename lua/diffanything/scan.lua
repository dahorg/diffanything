--- Recursive directory comparison.
local uv = vim.uv or vim.loop

local M = {}

---@alias diffanything.Status "modified"|"only_a"|"only_b"|"same"
---@class diffanything.Entry
---@field path string path relative to the compared roots
---@field status diffanything.Status

--- Collect every regular file below `root` (relative paths), honouring `ignore`
--- (a list of basenames that are neither listed nor descended into).
---@param root string
---@param ignore string[]
---@return table<string, true>
local function walk(root, ignore)
  local skip = {}
  for _, name in ipairs(ignore) do
    skip[name] = true
  end

  local files = {}
  local iter = vim.fs.dir(root, {
    depth = math.huge,
    skip = function(dir)
      return not skip[vim.fs.basename(dir)]
    end,
  })
  for name, kind in iter do
    if not skip[vim.fs.basename(name)] then
      if kind == "link" then
        local st = uv.fs_stat(root .. "/" .. name)
        kind = st and st.type or kind
      end
      if kind == "file" then
        files[name] = true
      end
    end
  end
  return files
end

---@param path string
---@return string?
local function read(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return nil
  end
  local st = uv.fs_fstat(fd)
  local data = st and uv.fs_read(fd, st.size, 0) or nil
  uv.fs_close(fd)
  return data
end

---@param a string
---@param b string
---@return boolean
local function same_content(a, b)
  local sa, sb = uv.fs_stat(a), uv.fs_stat(b)
  if not sa or not sb or sa.size ~= sb.size then
    return false
  end
  return read(a) == read(b)
end

---@param a string absolute directory
---@param b string absolute directory
---@param ignore string[]
---@return diffanything.Entry[]
function M.compare(a, b, ignore)
  local fa, fb = walk(a, ignore), walk(b, ignore)

  local entries = {}
  for path in pairs(fa) do
    local status
    if not fb[path] then
      status = "only_a"
    else
      status = same_content(a .. "/" .. path, b .. "/" .. path) and "same" or "modified"
    end
    entries[#entries + 1] = { path = path, status = status }
  end
  for path in pairs(fb) do
    if not fa[path] then
      entries[#entries + 1] = { path = path, status = "only_b" }
    end
  end

  table.sort(entries, function(x, y)
    return x.path < y.path
  end)
  return entries
end

--- True if the first chunk of the file contains a NUL byte.
---@param path string
---@return boolean
function M.is_binary(path)
  local fd = uv.fs_open(path, "r", 438)
  if not fd then
    return false
  end
  local chunk = uv.fs_read(fd, 8192, 0) or ""
  uv.fs_close(fd)
  return chunk:find("\0", 1, true) ~= nil
end

return M
