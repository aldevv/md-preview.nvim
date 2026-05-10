-- Globals exposed to plugin code (Neovim) and to plenary.busted specs.
std = "min+busted"
globals = { "vim" }

-- Plenary.busted injects describe/it/before_each/after_each via the runner;
-- declaring "+busted" above covers the names but we also tolerate the
-- assert.* style without complaint.
read_globals = { "assert" }

-- Plugin sources may import side-effect-only modules.
files["lua/md-preview/"] = {}
files["tests/"] = {
  -- Spec files frequently use unused arguments in stub callbacks.
  ignore = { "212/_.*", "213" },
}

-- 631 = "line is too long". Stylua wraps Lua at 140, but the AppleScript
-- template inside browser.lua is an embedded string stylua doesn't reflow —
-- 160 gives that one line headroom without losing the rule for real Lua.
max_line_length = 160
