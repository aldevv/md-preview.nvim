-- md-preview/init.lua — Neovim scroll-synced markdown preview
-- Single-instance: open → server + Chrome window
--                  re-open → replace content, no new server/window

local M = {}

-- Default leader keymaps registered on setup() unless opts.keymaps == false.
-- Pass a partial table to override individual entries; missing keys keep
-- their defaults. Set any value to false to skip just that one binding.
local DEFAULT_KEYMAPS = {
  open_dark  = "<leader>mv",
  open_light = "<leader>mV",
  close      = "<leader>mq",
}

local INSTALL_SCRIPT_URL = "https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh"
local INSTALL_HINT = "mdp binary not found. Install via `curl -fsSL " .. INSTALL_SCRIPT_URL .. " | sh`."

M.opts = {
  auto_position = true,   -- resize/reposition terminal + browser side-by-side
  keymaps       = true,   -- true = defaults | false = none | table = overrides
  colemak       = false,  -- swap in-page nav keys j/k/l → n/e/i
}

M.state = {
  job_id         = nil,   -- jobstart() channel ID
  port           = 9753,
  file           = nil,   -- absolute path currently previewed
  debounce_timer = nil,   -- vim.loop timer for cursor debounce
  platform       = nil,   -- "linux" or "macos"
  wm             = nil,   -- detected WM name on Linux ("xmonad", "dwm", ...)
  augroup        = nil,   -- autocmd group ID
}

-- WMs that tile automatically — launching the browser is enough, the WM
-- handles placement.
local AUTO_TILING_WMS = {
  xmonad = true, dwm = true, i3 = true, sway = true, bspwm = true,
  awesome = true, hyprland = true, river = true, qtile = true,
}

local function log(msg)
  vim.notify("[md-preview] " .. msg, vim.log.levels.DEBUG)
end

local function info(msg)
  vim.notify("[md-preview] " .. msg, vim.log.levels.INFO)
end

local function err(msg)
  vim.notify("[md-preview] " .. msg, vim.log.levels.ERROR)
end

-- ── Compat: vim.uv (0.10+) or vim.loop ───────────────────────────────────
local uv = vim.uv or vim.loop

-- close_timer is the only safe way to drop a uv timer. Both the debounce
-- cancellation path and the scheduled callback can race to close the same
-- handle: a timer fires, libuv queues its vim.schedule_wrap'd cb, and
-- before that cb runs another CursorMoved enters the cancellation path
-- and closes the handle. When the queued cb finally runs, calling
-- :close() again throws "handle is already closing". is_closing() makes
-- the close idempotent.
local function close_timer(t)
  if t and not t:is_closing() then
    t:stop()
    t:close()
  end
end

-- ── Platform detection ────────────────────────────────────────────────────

local function detect_wm()
  -- Try env first (cheap, set by most session managers).
  local env = os.getenv("XDG_CURRENT_DESKTOP")
      or os.getenv("DESKTOP_SESSION")
      or os.getenv("XDG_SESSION_DESKTOP")
  if env and env ~= "" then
    local first = env:lower():match("[%w_-]+")
    if first then return first end
  end
  -- Fallback: query root window via xprop.
  if vim.fn.executable("xprop") == 1 then
    local out = vim.fn.system("xprop -root _NET_WM_NAME 2>/dev/null")
    local name = out:match('"(.-)"')
    if name then return name:lower():match("[%w_-]+") end
  end
  return nil
end

-- resolve_keymaps merges the user's `keymaps` opt (true | false | table)
-- against DEFAULT_KEYMAPS. Returns nil when registration should be skipped.
local function resolve_keymaps(km)
  if km == false then return nil end
  if km == nil or km == true then return DEFAULT_KEYMAPS end
  if type(km) ~= "table" then
    err("opts.keymaps must be true, false, or a table — got " .. type(km))
    return DEFAULT_KEYMAPS
  end
  return vim.tbl_extend("force", DEFAULT_KEYMAPS, km)
end

local function register_keymaps(km)
  local map = function(lhs, rhs, desc)
    if not lhs then return end
    vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
  end
  map(km.open_dark,  function() M.open("dark")  end, "md-preview: open (dark)")
  map(km.open_light, function() M.open("light") end, "md-preview: open (light)")
  map(km.close,      function() M.close()       end, "md-preview: close")
end

function M.setup(opts)
  M.opts = vim.tbl_extend("force", M.opts, opts or {})

  local uname = uv.os_uname()
  if uname.sysname == "Darwin" then
    M.state.platform = "macos"
  else
    M.state.platform = "linux"
    M.state.wm = detect_wm()
  end

  local km = resolve_keymaps(M.opts.keymaps)
  if km then register_keymaps(km) end

  vim.api.nvim_create_user_command("MdPreviewInstall", function()
    M.install_cli()
  end, { desc = "Install the mdp CLI binary", force = true })

  -- Passive check on startup — don't auto-install. The plugin spec's
  -- `build = ...` step is the right place for one-shot install work; here
  -- we just nudge the user if the binary isn't on PATH yet.
  if vim.fn.executable("mdp") == 0 then
    vim.notify(
      "[md-preview] mdp not found. Run :MdPreviewInstall, or add `build = \"curl -fsSL "
        .. INSTALL_SCRIPT_URL .. " | sh\"` to your plugin spec.",
      vim.log.levels.WARN
    )
  end
end

-- ── CLI install ──────────────────────────────────────────────────────────
-- Delegates to the canonical install.sh in aldevv/md-preview, which uses
-- a prebuilt release binary (no Go toolchain needed). Only requirement
-- is curl + sh, which any system we'd run on already has.
--
-- Runs the curl|sh download asynchronously via jobstart so nvim doesn't
-- freeze during the download. Invoked via :MdPreviewInstall, or from a
-- plugin spec's build step (e.g. `build = ":MdPreviewInstall"` in
-- lazy.nvim). NOT called from setup() — startup is not the right place
-- for a one-shot install.
function M.install_cli()
  if vim.fn.executable("mdp") == 1 then return end

  if vim.fn.executable("curl") ~= 1 or vim.fn.executable("sh") ~= 1 then
    err(INSTALL_HINT)
    return
  end

  info("Installing mdp from github.com/aldevv/md-preview…")
  local stderr_lines = {}
  local job = vim.fn.jobstart(
    { "sh", "-c", "curl -fsSL " .. INSTALL_SCRIPT_URL .. " | sh" },
    {
      stderr_buffered = true,
      on_stderr = function(_, data)
        for _, line in ipairs(data or {}) do
          if line ~= "" then table.insert(stderr_lines, line) end
        end
      end,
      on_exit = function(_, code)
        if code == 0 then
          info("mdp installed")
        else
          err("install failed: " .. table.concat(stderr_lines, "\n") .. "\n" .. INSTALL_HINT)
        end
      end,
    }
  )
  if job <= 0 then
    err("install failed: jobstart returned " .. tostring(job) .. "\n" .. INSTALL_HINT)
  end
end

-- ── Server health check ───────────────────────────────────────────────────

function M.is_alive()
  if M.state.job_id == nil then return false end
  return vim.fn.jobwait({ M.state.job_id }, 0)[1] == -1
end

-- ── IPC: send JSON to server stdin ────────────────────────────────────────

local function send(msg)
  if not M.is_alive() then return end
  vim.fn.chansend(M.state.job_id, vim.json.encode(msg) .. "\n")
end

-- ── Poll until server is ready ────────────────────────────────────────────
-- TCP probe rather than shelling out to curl every 50ms — same readiness
-- signal (port accepts connections), no fork+exec on each retry.

local function poll_ready(port, on_ready, retries)
  retries = retries or 0
  if retries > 200 then
    err("Server did not start on port " .. port)
    return
  end
  local sock = uv.new_tcp()
  sock:connect("127.0.0.1", port, vim.schedule_wrap(function(connect_err)
    sock:close()
    if not connect_err then
      on_ready()
    else
      vim.defer_fn(function() poll_ready(port, on_ready, retries + 1) end, 50)
    end
  end))
end

-- ── Autocmds ─────────────────────────────────────────────────────────────

local function register_autocmds()
  if M.state.augroup then
    vim.api.nvim_del_augroup_by_id(M.state.augroup)
  end
  local aug = vim.api.nvim_create_augroup("MdPreview", { clear = true })
  M.state.augroup = aug

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    pattern = "*.md",
    callback = function()
      M.on_save()
    end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = aug,
    pattern = "*.md",
    callback = function()
      M.on_cursor_moved()
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = aug,
    pattern = "*.md",
    callback = function()
      local f = vim.fn.expand("<afile>:p")
      if f == M.state.file then
        M.close()
      end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function()
      M.close()
    end,
  })
end

-- ── Port conflict recovery ───────────────────────────────────────────────

-- Finds PIDs of `mdp serve` processes bound to `port` and kills them.
-- Scoped to our own server's command line so we never kill an unrelated
-- process that happens to share the port.
local function clear_stale_server(port)
  if vim.fn.executable("lsof") ~= 1 then return false end
  local pids_str = vim.fn.system("lsof -ti :" .. port .. " 2>/dev/null")
  local killed = {}
  for pid in pids_str:gmatch("%d+") do
    local cmdline = vim.fn.system("ps -o cmd= -p " .. pid .. " 2>/dev/null")
    if cmdline:match("mdp%s+serve") then
      vim.fn.system("kill " .. pid)
      table.insert(killed, pid)
    end
  end
  if #killed > 0 then
    -- Wait briefly for the socket to be released.
    vim.wait(500, function()
      local remaining = vim.fn.system("lsof -ti :" .. port .. " 2>/dev/null")
      return not remaining:match("%S")
    end)
    log("Cleared orphan md-preview server (pid " .. table.concat(killed, ",") .. ")")
    return true
  end
  return false
end

-- ── Open browser ─────────────────────────────────────────────────────────

local function find_chrome()
  local candidates = { "google-chrome", "chromium", "chromium-browser" }
  for _, c in ipairs(candidates) do
    if vim.fn.executable(c) == 1 then return c end
  end
  return nil
end

local function open_browser()
  local url = "http://localhost:" .. M.state.port .. "/"
  if M.state.platform == "macos" then
    if not M.opts.auto_position then
      vim.fn.jobstart(
        { "open", "-na", "Google Chrome", "--args", "--app=" .. url },
        { detach = true }
      )
      return
    end
    -- Open Chrome app window, then tile it to the right of kitty
    local script = string.format([[
-- Get screen bounds
tell application "Finder"
  set db to bounds of window of desktop
end tell
set screenLeft   to item 1 of db
set screenTop    to item 2 of db
set screenRight  to item 3 of db
set screenBottom to item 4 of db
set screenW to screenRight - screenLeft
set screenH to screenBottom - screenTop
set chromeX to screenLeft + (screenW * 6 div 10)
set chromeW to screenW - (screenW * 6 div 10)
-- Always tile kitty to left 60pct of screen
tell application "System Events"
  tell process "kitty"
    set position of window 1 to {screenLeft, screenTop}
    set size     of window 1 to {screenW * 6 div 10, screenH}
  end tell
end tell
-- Open Chrome with explicit size/position so it never restores fullscreen
do shell script "open -na 'Google Chrome' --args --app=%s --window-position=" & chromeX & "," & screenTop & " --window-size=" & chromeW & "," & screenH
-- Wait for Chrome window via System Events (up to 10 s)
repeat 20 times
  delay 0.5
  try
    tell application "System Events"
      tell process "Google Chrome"
        if (count windows) > 0 then exit repeat
      end tell
    end tell
  end try
end repeat
-- Fine-tune position (Chrome may ignore flags on first launch)
tell application "System Events"
  tell process "Google Chrome"
    set position of window 1 to {chromeX, screenTop}
    set size     of window 1 to {chromeW, screenH}
  end tell
end tell
]], url)
    vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
  else
    -- Linux: always launch detached. Known auto-tiling WMs handle placement;
    -- on unknown WMs we explicitly skip positioning per design.
    local chrome = find_chrome()
    if not chrome then
      err("No Chrome/Chromium found")
      return
    end
    vim.fn.jobstart({ chrome, "--app=" .. url }, { detach = true })
    if M.opts.auto_position then
      if M.state.wm and AUTO_TILING_WMS[M.state.wm] then
        log("WM " .. M.state.wm .. " will tile chromium")
      else
        log("WM " .. (M.state.wm or "unknown") .. " — launched without positioning")
      end
    end
  end
end

-- ── Main API ──────────────────────────────────────────────────────────────

function M.open(theme)
  theme = theme or "dark"
  local file = vim.fn.expand("%:p")

  if not file:match("%.md$") then
    err("Not a markdown file")
    return
  end

  -- Already running: switch file only
  if M.is_alive() then
    M.state.file = file
    send({ type = "render", file = file })
    log("Switched preview to " .. vim.fn.fnamemodify(file, ":t"))
    return
  end

  M.state.file = file

  -- If a previous nvim session left a server bound to our port (e.g. plugin
  -- was reloaded without close()), kill it before binding.
  clear_stale_server(M.state.port)

  if vim.fn.executable("mdp") == 0 then
    err(INSTALL_HINT)
    return
  end

  local job_env = nil
  if M.opts.colemak then job_env = { MDP_COLEMAK = "1" } end

  M.state.job_id = vim.fn.jobstart(
    { "mdp", "serve", file, tostring(M.state.port), theme },
    {
      stdin = "pipe",
      stdout_buffered = false,
      stderr_buffered = false,
      env = job_env,
      on_stdout = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then log(line) end
        end
      end,
      on_stderr = function(_, data)
        for _, line in ipairs(data) do
          if line ~= "" then err(line) end
        end
      end,
      on_exit = function(_, code)
        if code ~= 0 then
          err("Server exited with code " .. code)
        end
        M.state.job_id = nil
      end,
    }
  )

  if M.state.job_id <= 0 then
    err("Failed to start server")
    M.state.job_id = nil
    return
  end

  info("Starting server for " .. vim.fn.fnamemodify(file, ":t") .. "…")

  poll_ready(M.state.port, function()
    log("Server ready — opening browser")
    open_browser()
    register_autocmds()
  end)
end

-- ── Cursor moved (debounced 50ms) ────────────────────────────────────────

function M.on_cursor_moved()
  if not M.is_alive() then return end

  close_timer(M.state.debounce_timer)
  M.state.debounce_timer = nil

  local timer = uv.new_timer()
  M.state.debounce_timer = timer
  timer:start(50, 0, vim.schedule_wrap(function()
    -- A fresher CursorMoved may have already replaced us. If so, the
    -- cancellation path closed our handle; bail without re-firing.
    if M.state.debounce_timer ~= timer then return end
    M.state.debounce_timer = nil
    close_timer(timer)
    if not M.is_alive() then return end
    -- cursor row is 1-indexed — matches data-line values in browser
    local row = vim.api.nvim_win_get_cursor(0)[1]
    send({ type = "scroll", line = row })
  end))
end

-- ── Save ──────────────────────────────────────────────────────────────────

function M.on_save()
  if not M.is_alive() then return end
  local file = vim.fn.expand("%:p")
  M.state.file = file
  send({ type = "render", file = file })
end

-- ── Close ─────────────────────────────────────────────────────────────────

function M.close()
  close_timer(M.state.debounce_timer)
  M.state.debounce_timer = nil

  if M.is_alive() then
    send({ type = "quit" })
    vim.fn.jobstop(M.state.job_id)
  end

  -- Close the Chrome --app window that's serving our port
  if M.state.platform == "macos" then
    local port = M.state.port
    vim.fn.jobstart({
      "osascript", "-e", string.format([[
tell application "System Events"
  tell process "Google Chrome"
    set wins to windows
    repeat with w in wins
      try
        if title of w contains "localhost:%d" then
          click button 1 of w
        end if
      end try
    end repeat
  end tell
end tell
]], port),
    }, { detach = true })
  elseif M.state.platform == "linux" then
    -- Chromium with --app= shares the existing chromium master process via
    -- IPC, so jobstop on our launcher does nothing visible. Match the
    -- window by title (--app= URL appears in the title) and ask the WM to
    -- close it gently.
    local title = "localhost:" .. M.state.port
    if vim.fn.executable("xdotool") == 1 then
      vim.fn.system("xdotool search --name " .. vim.fn.shellescape(title)
        .. " windowclose 2>/dev/null")
    elseif vim.fn.executable("wmctrl") == 1 then
      vim.fn.system("wmctrl -c " .. vim.fn.shellescape(title) .. " 2>/dev/null")
    end
  end

  if M.state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, M.state.augroup)
  end

  M.state.job_id  = nil
  M.state.file    = nil
  M.state.augroup = nil

  log("Preview closed")
end

return M
