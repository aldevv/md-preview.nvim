-- M.opts / M.state in init.lua alias these tables — mutate in place;
-- replacing the tables breaks the aliases.

return {
  opts = {
    auto_position = true,
    keymaps = true,
    colemak = false, -- swap in-page nav keys j/k/l → n/e/i
    port = 9753,
    terminal_app = "kitty", -- macOS: process name to tile beside Chrome
    prefer_global_mdp = false, -- true: pick the system-installed `mdp` from $PATH first, fall back to <plugin_root>/bin/mdp
  },

  state = {
    job_id = nil,
    file = nil,
    platform = nil, -- "linux" | "macos" | nil (unsupported)
    wm = nil, -- detected WM name on Linux ("xmonad", "dwm", ...)
    augroup = nil,
  },
}
