-- Async install via canonical install.sh in aldevv/md-preview (prebuilt
-- binary, no Go toolchain). Runs via jobstart so nvim doesn't freeze.
-- NOT called from setup() — startup is not the place for one-shot work;
-- use a plugin-spec build step (e.g. `build = ":MdPreviewInstall"`).

local notify = require("md-preview.notify")

local M = {}

M.SCRIPT_URL = "https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh"
M.HINT = "mdp binary not found. Install via `curl -fsSL " .. M.SCRIPT_URL .. " | sh`."

function M.run()
  if vim.fn.executable("mdp") == 1 then return end

  if vim.fn.executable("curl") ~= 1 or vim.fn.executable("sh") ~= 1 then
    notify.err(M.HINT)
    return
  end

  notify.info("Installing mdp from github.com/aldevv/md-preview…")
  local stderr_lines = {}
  local job = vim.fn.jobstart({ "sh", "-c", "curl -fsSL " .. M.SCRIPT_URL .. " | sh" }, {
    stderr_buffered = true,
    on_stderr = function(_, data)
      for _, line in ipairs(data or {}) do
        if line ~= "" then table.insert(stderr_lines, line) end
      end
    end,
    on_exit = function(_, code)
      if code == 0 then
        notify.info("mdp installed")
      else
        notify.err("install failed: " .. table.concat(stderr_lines, "\n") .. "\n" .. M.HINT)
      end
    end,
  })
  if job <= 0 then notify.err("install failed: jobstart returned " .. tostring(job) .. "\n" .. M.HINT) end
end

return M
