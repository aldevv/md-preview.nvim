-- `:MdPreviewInstall` drops mdp at <plugin_root>/bin/mdp; resolve_mdp
-- prefers that copy and falls back to `mdp` on $PATH.

local M = {}

local _root

function M.plugin_root()
  if _root then return _root end
  local src = debug.getinfo(1, "S").source
  if src:sub(1, 1) == "@" then src = src:sub(2) end
  _root = vim.fn.fnamemodify(src, ":h:h:h")
  return _root
end

function M.mdp_bin() return M.plugin_root() .. "/bin/mdp" end

function M.resolve_mdp()
  local in_tree = M.mdp_bin()
  if vim.fn.executable(in_tree) == 1 then return in_tree end
  if vim.fn.executable("mdp") == 1 then return "mdp" end
  return nil
end

function M.mdp_available() return M.resolve_mdp() ~= nil end

return M
