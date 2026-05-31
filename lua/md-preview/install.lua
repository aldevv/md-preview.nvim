-- Async install via canonical install.sh in aldevv/md-preview. Drops the
-- binary at <plugin_root>/bin/mdp so the install is self-contained to this
-- lazy.nvim checkout. NOT called from setup(); wire as `build = ":MdPreviewInstall"`.

local notify = require("md-preview.notify")
local paths = require("md-preview.paths")

local M = {}

M.SCRIPT_URL = "https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh"
M.HINT = "mdp binary not found. Run :MdPreviewInstall, or curl -fsSL " .. M.SCRIPT_URL .. " | sh."

-- The pinned CLI version lives in <plugin_root>/mdp-version.txt. Shipped as a
-- plain-text file so CI can rewrite it without touching Lua source. A GitHub
-- Actions workflow in this repo bumps it whenever the aldevv/md-preview repo
-- cuts a release (via repository_dispatch), then tags a patch release here so
-- the next `build = ":MdPreviewInstall"` run pulls the matching binary.
function M.pinned_version()
  local path = paths.plugin_root() .. "/mdp-version.txt"
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or not lines or #lines == 0 then return nil end
  return (lines[1]:gsub("^%s+", ""):gsub("%s+$", ""))
end

-- Returns the version string reported by an in-tree mdp binary, or nil if
-- the binary is missing or errored. Used to short-circuit when what's on disk
-- already matches the pinned version — avoids a curl | sh round-trip on every
-- lazy.nvim sync.
function M.installed_version()
  local bin = paths.mdp_bin()
  if vim.fn.executable(bin) ~= 1 then return nil end
  local ok, out = pcall(vim.fn.system, { bin, "version" })
  if not ok or vim.v.shell_error ~= 0 then return nil end
  return (out:gsub("^%s+", ""):gsub("%s+$", ""))
end

function M.run()
  local pinned = M.pinned_version()
  if vim.fn.executable(paths.mdp_bin()) == 1 then
    if not pinned or pinned == "" then return end
    if M.installed_version() == pinned then return end
  end

  if vim.fn.executable("curl") ~= 1 or vim.fn.executable("sh") ~= 1 then
    notify.err(M.HINT)
    return
  end

  -- PREFIX/MDP_VERSION must sit on the `sh` end of the pipe; on `curl` they
  -- wouldn't cross to the separate sh process that actually reads the script.
  local prefix = vim.fn.shellescape(paths.plugin_root())
  local env = "PREFIX=" .. prefix
  if pinned and pinned ~= "" then env = env .. " MDP_VERSION=" .. vim.fn.shellescape(pinned) end
  local cmd = "curl -fsSL " .. M.SCRIPT_URL .. " | " .. env .. " sh"

  local msg = "Installing mdp into " .. paths.plugin_root() .. "/bin"
  if pinned then msg = msg .. " (" .. pinned .. ")" end
  notify.info(msg .. " …")
  local stderr_lines = {}
  local job = vim.fn.jobstart({ "sh", "-c", cmd }, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then table.insert(stderr_lines, line) end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        notify.info("mdp installed at " .. paths.mdp_bin())
      else
        notify.err("install failed: " .. table.concat(stderr_lines, "\n") .. "\n" .. M.HINT)
      end
    end,
  })
  if job <= 0 then notify.err("install failed: jobstart returned " .. tostring(job) .. "\n" .. M.HINT) end
end

return M
