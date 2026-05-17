-- Handle "[md-preview] navigate: <abs-path>" lines the mdp server emits on
-- stdout when a click in the preview switches to a different .md file.
-- Keeps the editor buffer aligned with what the preview is showing.

local notify = require("md-preview.notify")
local store = require("md-preview.state")

local M = {}

local NAVIGATE_PREFIX = "[md-preview] navigate: "

function M.parse(line)
  if type(line) ~= "string" then return nil end
  if line:sub(1, #NAVIGATE_PREFIX) ~= NAVIGATE_PREFIX then return nil end
  local path = line:sub(#NAVIGATE_PREFIX + 1)
  if path == "" then return nil end
  return path
end

-- find_window returns the (tabnr, winid) showing target_file, or (nil, nil).
-- Scans the current tab first so a multi-tab user lands somewhere predictable.
local function find_window(target_file)
  local function scan(tabnr)
    for _, win in ipairs(vim.api.nvim_tabpage_list_wins(tabnr)) do
      local buf = vim.api.nvim_win_get_buf(win)
      local name = vim.api.nvim_buf_get_name(buf)
      if name ~= "" and vim.fn.fnamemodify(name, ":p") == target_file then return tabnr, win end
    end
    return nil, nil
  end
  local current_tab = vim.api.nvim_get_current_tabpage()
  local tabnr, win = scan(current_tab)
  if win then return tabnr, win end
  for _, t in ipairs(vim.api.nvim_list_tabpages()) do
    if t ~= current_tab then
      tabnr, win = scan(t)
      if win then return tabnr, win end
    end
  end
  return nil, nil
end

-- follow switches the window currently showing state.file to new_file via
-- :edit. If no such window exists, leaves the editor alone and notifies; the
-- user is presumably off doing something else and a surprise buffer-swap
-- would be worse than silence. Updates state.file so subsequent scroll
-- events track the new buffer.
function M.follow(new_file)
  if not new_file or new_file == "" then return end
  if new_file == store.state.file then return end

  local prev_file = store.state.file
  local target_win = nil
  if prev_file then
    local _, win = find_window(prev_file)
    target_win = win
  end

  if not target_win then
    notify.log("Preview navigated to " .. vim.fn.fnamemodify(new_file, ":t") .. " (no matching editor window)")
    store.state.file = new_file
    return
  end

  local prev_win = vim.api.nvim_get_current_win()
  vim.api.nvim_set_current_win(target_win)
  local ok, err = pcall(vim.cmd.edit, vim.fn.fnameescape(new_file))
  if not ok then
    notify.err("md-preview: could not :edit " .. new_file .. ": " .. tostring(err))
    pcall(vim.api.nvim_set_current_win, prev_win)
    return
  end
  store.state.file = new_file
  if prev_win ~= target_win and vim.api.nvim_win_is_valid(prev_win) then
    vim.api.nvim_set_current_win(prev_win)
  end
end

return M
