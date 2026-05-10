local M = {}

M.uv = vim.uv or vim.loop  -- vim.uv on 0.10+, vim.loop on older builds

-- WMs that already tile windows on launch — the launcher just spawns the
-- browser; the WM places it.
M.AUTO_TILING_WMS = {
  xmonad = true, dwm = true, i3 = true, sway = true, bspwm = true,
  awesome = true, hyprland = true, river = true, qtile = true,
}

function M.detect_wm()
  local env = os.getenv("XDG_CURRENT_DESKTOP")
      or os.getenv("DESKTOP_SESSION")
      or os.getenv("XDG_SESSION_DESKTOP")
  if env and env ~= "" then
    local first = env:lower():match("[%w_-]+")
    if first then return first end
  end
  if vim.fn.executable("xprop") == 1 then
    local out = vim.fn.system("xprop -root _NET_WM_NAME 2>/dev/null")
    local name = out:match('"(.-)"')
    if name then return name:lower():match("[%w_-]+") end
  end
  return nil
end

function M.find_chrome()
  local candidates = { "google-chrome", "chromium", "chromium-browser" }
  for _, c in ipairs(candidates) do
    if vim.fn.executable(c) == 1 then return c end
  end
  return nil
end

return M
