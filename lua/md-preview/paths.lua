-- `:MdPreviewInstall` drops mdp at <plugin_root>/bin/mdp; by default
-- resolve_mdp prefers that copy and falls back to `mdp` on $PATH. Set
-- `prefer_global_mdp = true` in setup() to flip the order so a globally
-- installed mdp on $PATH wins over the pinned in-tree binary.

local store = require("md-preview.state")

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
  local in_tree_ok = vim.fn.executable(in_tree) == 1
  local path_ok = vim.fn.executable("mdp") == 1
  if store.opts.prefer_global_mdp then
    if path_ok then return "mdp" end
    if in_tree_ok then return in_tree end
  else
    if in_tree_ok then return in_tree end
    if path_ok then return "mdp" end
  end
  return nil
end

function M.mdp_available() return M.resolve_mdp() ~= nil end

return M
