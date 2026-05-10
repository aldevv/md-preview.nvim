local notify = require("md-preview.notify")
local platform = require("md-preview.platform")
local store = require("md-preview.state")

local M = {}

function M.open()
  local s = store.state
  local url = "http://localhost:" .. store.opts.port .. "/"

  if s.platform == "macos" then
    if not store.opts.auto_position then
      vim.fn.jobstart({ "open", "-na", "Google Chrome", "--args", "--app=" .. url }, { detach = true })
      return
    end
    -- Tile `terminal_app` to the left 60% and Chrome to the right 40%. The
    -- terminal-app block is wrapped in `try` so users on a different
    -- terminal (alacritty, wezterm, iTerm2, Terminal, Ghostty) just skip
    -- the resize step rather than seeing an AppleScript error dialog.
    local term = (store.opts.terminal_app or "kitty"):gsub('"', '\\"')
    local script = string.format(
      [[
tell application "Finder"
  set db to bounds of window of desktop
end tell
set screenLeft   to item 1 of db
set screenTop    to item 2 of db
set screenRight  to item 3 of db
set screenBottom to item 4 of db
set screenW to screenRight - screenLeft
set screenH to screenBottom - screenTop
set chromeX to screenLeft + (screenW * 6 div 10)
set chromeW to screenW - (screenW * 6 div 10)
try
  tell application "System Events"
    tell process "%s"
      set position of window 1 to {screenLeft, screenTop}
      set size     of window 1 to {screenW * 6 div 10, screenH}
    end tell
  end tell
end try
-- Explicit size/position so Chrome never restores fullscreen
do shell script "open -na 'Google Chrome' --args --app=%s --window-position=" & chromeX & "," & screenTop & " --window-size=" & chromeW & "," & screenH
repeat 20 times
  delay 0.5
  try
    tell application "System Events"
      tell process "Google Chrome"
        if (count windows) > 0 then exit repeat
      end tell
    end tell
  end try
end repeat
-- Fine-tune position (Chrome may ignore flags on first launch)
tell application "System Events"
  tell process "Google Chrome"
    set position of window 1 to {chromeX, screenTop}
    set size     of window 1 to {chromeW, screenH}
  end tell
end tell
]],
      term,
      url
    )
    vim.fn.jobstart({ "osascript", "-e", script }, { detach = true })
    return
  end

  local chrome = platform.find_chrome()
  if not chrome then
    notify.err("No Chrome/Chromium found")
    return
  end
  vim.fn.jobstart({ chrome, "--app=" .. url }, { detach = true })
  -- Known auto-tilers handle placement; on unknown WMs we skip positioning.
  if store.opts.auto_position then
    if s.wm and platform.AUTO_TILING_WMS[s.wm] then
      notify.log("WM " .. s.wm .. " will tile chromium")
    else
      notify.log("WM " .. (s.wm or "unknown") .. " — launched without positioning")
    end
  end
end

function M.close_window()
  local s = store.state
  if s.platform == "macos" then
    local port = store.opts.port
    vim.fn.jobstart({
      "osascript",
      "-e",
      string.format(
        [[
tell application "System Events"
  tell process "Google Chrome"
    set wins to windows
    repeat with w in wins
      try
        if title of w contains "localhost:%d" then
          click button 1 of w
        end if
      end try
    end repeat
  end tell
end tell
]],
        port
      ),
    }, { detach = true })
  elseif s.platform == "linux" then
    -- Chromium with --app= shares the master process via IPC, so jobstop
    -- on our launcher does nothing visible. Match the window by title and
    -- ask the WM to close it.
    local title = "localhost:" .. store.opts.port
    if vim.fn.executable("xdotool") == 1 then
      vim.fn.system("xdotool search --name " .. vim.fn.shellescape(title) .. " windowclose 2>/dev/null")
    elseif vim.fn.executable("wmctrl") == 1 then
      vim.fn.system("wmctrl -c " .. vim.fn.shellescape(title) .. " 2>/dev/null")
    end
    -- Pure Wayland sessions: xdotool/wmctrl are X11-only. If the Chrome
    -- window was launched as native Wayland, neither tool can see it.
    -- Warn rather than silently leaving the window orphaned.
    local wayland = os.getenv("WAYLAND_DISPLAY")
    if wayland and wayland ~= "" and vim.fn.executable("xdotool") ~= 1 and vim.fn.executable("wmctrl") ~= 1 then
      notify.warn("xdotool/wmctrl not available on this Wayland session — " .. "close the preview window manually")
    end
  end
end

return M
