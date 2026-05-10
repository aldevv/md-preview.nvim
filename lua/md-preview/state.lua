-- M.opts / M.state in init.lua alias these tables — mutate in place;
-- replacing the tables breaks the aliases.

return {
  opts = {
    auto_position = true,
    keymaps = true,
    colemak = false, -- swap in-page nav keys j/k/l → n/e/i
    port = 9753,
    terminal_app = "kitty", -- macOS: process name to tile beside Chrome
  },

  state = {
    job_id = nil,
    file = nil,
    platform = nil, -- "linux" | "macos" | nil (unsupported)
    wm = nil, -- detected WM name on Linux ("xmonad", "dwm", ...)
    augroup = nil,
  },
}
