-- md-preview/init.lua — Neovim scroll-synced markdown preview.
-- Single-instance: open → server + Chrome window; re-open → render-only.

local store = require("md-preview.state")
local notify = require("md-preview.notify")
local platform = require("md-preview.platform")
local paths = require("md-preview.paths")
local ipc = require("md-preview.ipc")
local server = require("md-preview.server")

local M = {}

-- Aliases by reference: submodules mutate the same singleton tables.
M.opts = store.opts
M.state = store.state

M.is_alive = server.is_alive
M.install_cli = function() return require("md-preview.install").run() end

local _initialized = false

function M.setup(opts)
  for k, v in pairs(opts or {}) do
    M.opts[k] = v
  end
  -- Side effects (platform detect, keymaps, user command) run once. Opts
  -- can still be merged on subsequent calls; only the wiring is one-shot.
  if _initialized then return end
  _initialized = true

  local uname = platform.uv.os_uname()
  if uname.sysname == "Darwin" then
    M.state.platform = "macos"
  elseif uname.sysname:find("Windows") or uname.sysname:find("MINGW") or uname.sysname:find("MSYS") then
    M.state.platform = nil
    notify.warn("md-preview: native Windows is not supported (sysname=" .. uname.sysname .. ")")
  else
    M.state.platform = "linux"
    M.state.wm = platform.detect_wm()
  end

  local keymaps = require("md-preview.keymaps")
  local km = keymaps.resolve(M.opts.keymaps)
  if km then keymaps.register(km, M) end

  vim.api.nvim_create_user_command(
    "MdPreviewInstall",
    function() M.install_cli() end,
    { desc = "Install the mdp CLI binary", force = true }
  )

  -- Passive nudge — startup is not the place for shell-out install work;
  -- the plugin spec's `build = ...` step is.
  if not paths.mdp_available() then
    notify.warn("mdp not found. Run :MdPreviewInstall, or add " .. '`build = ":MdPreviewInstall"` to your plugin spec.')
  end
end

function M.open(theme)
  theme = theme or "dark"
  local file = vim.fn.expand("%:p")

  if not file:match("%.md$") then
    notify.err("Not a markdown file")
    return
  end

  if not M.state.platform then
    notify.err("md-preview: platform unsupported, cannot open preview")
    return
  end

  -- Respawn rather than reuse: re-opening after the user manually closed
  -- the Chrome window would otherwise render to an orphan server.
  if M.is_alive() then
    M.close()
    server.wait_port_free(M.opts.port)
  end

  M.state.file = file

  -- A previous nvim session may have left a server bound to our port.
  server.clear_stale(M.opts.port)

  local mdp = paths.resolve_mdp()
  if not mdp then
    notify.err(require("md-preview.install").HINT)
    return
  end

  local job_env = nil
  if M.opts.colemak then job_env = { MDP_COLEMAK = "1" } end

  M.state.job_id = vim.fn.jobstart({ mdp, "serve", file, tostring(M.opts.port), theme }, {
    stdin = "pipe",
    stdout_buffered = false,
    stderr_buffered = false,
    env = job_env,
    on_stdout = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then notify.log(line) end
      end
    end,
    on_stderr = function(_, data)
      for _, line in ipairs(data) do
        if line ~= "" then notify.err(line) end
      end
    end,
    on_exit = function(job, code)
      if code ~= 0 then notify.err("Server exited with code " .. code) end
      -- Old job's on_exit can fire after respawn has set a new job_id;
      -- guard against clobbering the live server's id.
      if M.state.job_id == job then M.state.job_id = nil end
    end,
  })

  if M.state.job_id <= 0 then
    notify.err("Failed to start server")
    M.state.job_id = nil
    return
  end

  -- Register autocmds before poll_ready so VimLeavePre / BufWipeout cover
  -- the server-start window (up to ~10s). BufWritePost / CursorMoved gate
  -- on M.is_alive() — they no-op until the server is actually up.
  require("md-preview.autocmds").register(M)

  notify.info("Starting server for " .. vim.fn.fnamemodify(file, ":t") .. "…")

  ipc.poll_ready(M.opts.port, function()
    notify.log("Server ready — opening browser")
    require("md-preview.browser").open()
  end)
end

function M.on_cursor_moved()
  -- The autocmd pattern is "*.md" (not buffer-local) so file switches
  -- still work; short-circuit here when CursorMoved fires in some other
  -- markdown buffer.
  if vim.fn.expand("%:p") ~= M.state.file then return end
  if not M.is_alive() then return end
  ipc.debounce_scroll(function() return vim.api.nvim_win_get_cursor(0)[1] end)
end

function M.on_save()
  if not M.is_alive() then return end
  local file = vim.fn.expand("%:p")
  M.state.file = file
  ipc.send({ type = "render", file = file })
end

function M.close()
  ipc.cancel_debounce()

  if M.is_alive() then
    ipc.send({ type = "quit" })
    vim.fn.jobstop(M.state.job_id)
  end

  require("md-preview.browser").close_window()

  if M.state.augroup then pcall(vim.api.nvim_del_augroup_by_id, M.state.augroup) end

  M.state.job_id = nil
  M.state.file = nil
  M.state.augroup = nil

  notify.log("Preview closed")
end

return M
