local notify = require("md-preview.notify")
local store  = require("md-preview.state")

local M = {}

function M.is_alive()
  if store.state.job_id == nil then return false end
  return vim.fn.jobwait({ store.state.job_id }, 0)[1] == -1
end

-- Scoped to processes whose executable basename is exactly `mdp` so we
-- never kill an unrelated process that happens to share the port.
-- `ps -o comm=` is portable across Linux + macOS (vs `-o cmd=` which
-- differs); the basename trim handles ps' trailing newline.
function M.clear_stale(port)
  if vim.fn.executable("lsof") ~= 1 then return false end
  local pids_str = vim.fn.system("lsof -ti :" .. port .. " 2>/dev/null")
  local killed = {}
  for pid in pids_str:gmatch("%d+") do
    local basename = vim.fn.system("ps -o comm= -p " .. pid .. " 2>/dev/null")
      :gsub("%s+$", "")
    if basename == "mdp" then
      vim.fn.system("kill " .. pid)
      table.insert(killed, pid)
    end
  end
  if #killed > 0 then
    notify.log("Cleared orphan md-preview server (pid " .. table.concat(killed, ",") .. ")")
    return true
  end
  return false
end

return M
