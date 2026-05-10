-- opts.keymaps shape: true → register defaults, false → register none,
-- table → merge over defaults (per-key `false` skips just that binding).

local notify = require("md-preview.notify")

local M = {}

M.DEFAULTS = {
  open_dark = "<leader>mv",
  open_light = "<leader>mV",
  close = "<leader>mq",
}

function M.resolve(km)
  if km == false then return nil end
  if km == nil or km == true then return M.DEFAULTS end
  if type(km) ~= "table" then
    notify.err("opts.keymaps must be true, false, or a table — got " .. type(km))
    return M.DEFAULTS
  end
  return vim.tbl_extend("force", M.DEFAULTS, km)
end

function M.register(km, plugin)
  local map = function(lhs, rhs, desc)
    if not lhs then return end
    vim.keymap.set("n", lhs, rhs, { silent = true, desc = desc })
  end
  map(km.open_dark, function() plugin.open("dark") end, "md-preview: open (dark)")
  map(km.open_light, function() plugin.open("light") end, "md-preview: open (light)")
  map(km.close, function() plugin.close() end, "md-preview: close")
end

return M
