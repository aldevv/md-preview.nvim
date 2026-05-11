-- Async install via canonical install.sh in aldevv/md-preview. Drops the
-- binary at <plugin_root>/bin/mdp so the install is self-contained to this
-- lazy.nvim checkout. NOT called from setup(); wire as `build = ":MdPreviewInstall"`.

local notify = require("md-preview.notify")
local paths = require("md-preview.paths")

local M = {}

M.SCRIPT_URL = "https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh"
M.HINT = "mdp binary not found. Run :MdPreviewInstall, or curl -fsSL " .. M.SCRIPT_URL .. " | sh."

function M.run()
  if vim.fn.executable(paths.mdp_bin()) == 1 then return end

  if vim.fn.executable("curl") ~= 1 or vim.fn.executable("sh") ~= 1 then
    notify.err(M.HINT)
    return
  end

  -- PREFIX must sit on the `sh` end of the pipe; on `curl` it wouldn't cross
  -- the pipe to the separate sh process that actually reads it.
  local prefix = vim.fn.shellescape(paths.plugin_root())
  local cmd = "curl -fsSL " .. M.SCRIPT_URL .. " | PREFIX=" .. prefix .. " sh"

  notify.info("Installing mdp into " .. paths.plugin_root() .. "/bin …")
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
