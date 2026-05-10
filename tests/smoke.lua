local results = { steps = {}, ok = true }

local function step(name, ok, detail)
  table.insert(results.steps, { name = name, ok = ok, detail = detail })
  if not ok then results.ok = false end
  io.write(string.format("[%s] %s%s\n", ok and "ok" or "FAIL", name, detail and ("  " .. detail) or ""))
end

local sample_path = vim.fn.getcwd() .. "/tests/smoke_sample.md"
vim.fn.writefile({
  "# Smoke",
  "",
  "first paragraph",
  "",
  "second paragraph",
}, sample_path)
vim.cmd("e " .. sample_path)

local saved_jobstart = vim.fn.jobstart
vim.fn.jobstart = function(cmd, opts)
  if type(cmd) == "table" then
    for _, c in ipairs(cmd) do
      if type(c) == "string" and (c:match("chrom") or c == "open" or c == "osascript" or c == "xdotool" or c == "wmctrl") then
        return 999
      end
    end
  end
  return saved_jobstart(cmd, opts)
end

local function curl(url, method, body)
  local args = { "curl", "-sf", "--max-time", "1" }
  if method == "POST" then
    table.insert(args, "-X")
    table.insert(args, "POST")
    if body then
      table.insert(args, "-d")
      table.insert(args, body)
    end
  end
  table.insert(args, url)
  return vim.fn.system(args), vim.v.shell_error
end

local m = require("md-preview")
local ipc = require("md-preview.ipc")
m.setup({ port = 9999, auto_position = false })

m.open("dark")
step("M.open returned without error", m.is_alive(), "is_alive=" .. tostring(m.is_alive()))

local server_up = vim.wait(3000, function()
  local _, code = curl("http://localhost:9999/reload")
  return code == 0
end, 50)
step("server responding on /reload within 3s", server_up)

local body = curl("http://localhost:9999/")
step(
  "GET / returns rendered HTML",
  type(body) == "string" and body:find("<h1", 1, true) ~= nil and body:find("Smoke", 1, true) ~= nil,
  "len=" .. tostring(#body)
)

local v1 = curl("http://localhost:9999/reload")
local ver1 = v1 and v1:match('"version":(%d+)')
step("initial version readable", ver1 ~= nil, "version=" .. tostring(ver1))

vim.fn.writefile({
  "# Smoke",
  "",
  "first paragraph",
  "",
  "second paragraph (edited)",
  "",
  "third paragraph",
}, sample_path)
vim.cmd("e!")
m.on_save()

local bumped = vim.wait(1500, function()
  local reload, code = curl("http://localhost:9999/reload")
  if code ~= 0 or not reload then return false end
  local ver = tonumber(reload:match('"version":(%d+)'))
  return ver and ver1 and ver > tonumber(ver1)
end, 50)
step("on_save bumps version on the server", bumped)

local v2 = curl("http://localhost:9999/")
step("re-rendered body contains the edit", type(v2) == "string" and v2:find("(edited)", 1, true) ~= nil)

m.on_cursor_moved()
local cursor_ok = vim.wait(500, function() return not ipc.has_pending_timer() end, 50)
step("cursor-move debounce fires and clears timer", cursor_ok)

m.close()
local server_dead = vim.wait(2000, function()
  local _, code = curl("http://localhost:9999/reload")
  return code ~= 0
end, 50)
step("M.close stops the server", server_dead)

vim.fn.delete(sample_path)

io.write(string.format(
  "\n%s: %d/%d steps passed\n",
  results.ok and "PASS" or "FAIL",
  (function()
    local n = 0
    for _, s in ipairs(results.steps) do
      if s.ok then n = n + 1 end
    end
    return n
  end)(),
  #results.steps
))
os.exit(results.ok and 0 or 1)
