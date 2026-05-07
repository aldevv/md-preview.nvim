# md-preview.nvim

Scroll-synced markdown preview for Neovim, plus a standalone `mdp` CLI for one-shot rendering — both backed by `markdown-it-py` and a single shared renderer.

## Features

- Live preview that follows your cursor and re-renders on save (Neovim plugin).
- Standalone `mdp` CLI: `mdp file.md` opens a static rendered HTML in Chrome `--app=` (or your browser of choice).
- Self-bootstrapping Python venv — no global pip installs required.
- Dark / light themes, GitHub-flavored markdown, task lists, syntax highlighting via highlight.js.
- Frontmatter is stripped, not rendered.

## Install (lazy.nvim)

```lua
{
  "aldevv/md-preview.nvim",
  ft = { "markdown" },
  config = function()
    require("md-preview").setup()
  end,
}
```

The plugin auto-symlinks `~/.local/bin/mdp` to the bundled CLI on `setup()`.

## Plugin usage

```lua
require("md-preview").open("dark")   -- or "light"
require("md-preview").close()
```

Suggested keymaps:

```lua
vim.keymap.set("n", "<leader>mv", function() require("md-preview").open("dark") end)
vim.keymap.set("n", "<leader>mV", function() require("md-preview").open("light") end)
vim.keymap.set("n", "<leader>mq", function() require("md-preview").close() end)
```

While open, `BufWritePost` re-renders, `CursorMoved` syncs scroll (debounced), `BufWipeout` of the previewed file closes the server.

## CLI install (no Neovim required)

One-liner:

```sh
curl -fsSL https://raw.githubusercontent.com/aldevv/md-preview.nvim/main/install.sh | sh
```

This clones the repo to `~/.local/share/md-preview` and symlinks `~/.local/bin/mdp`. Override the prefix with `PREFIX=...`:

```sh
PREFIX=/usr/local sh install.sh   # system-wide
```

Update later with `git -C ~/.local/share/md-preview pull` (or re-run the installer).

The Neovim plugin already auto-symlinks `mdp` on `setup()`, so plugin users don't need this.

## CLI usage

```sh
mdp                        # fzf-pick a .md from cwd, then preview
mdp README.md              # render + open in browser
mdp -e README.md           # preview AND open the file in nvim
mdp -e                     # fzf-pick, preview, and edit
mdp -t light README.md     # light theme
mdp -p README.md           # print HTML path, don't open browser
```

If `fzf` is not installed and you run `mdp` with no file argument, it prints `--help` plus a note about installing fzf.

`-e` opens nvim after spawning the browser preview (the preview is static — re-run `mdp` if you want it to reflect new edits, or use the Neovim plugin's live-sync command instead).

### Config — `~/.config/md-preview/config.toml`

All keys optional:

```toml
theme      = "dark"          # "dark" or "light"
font_size  = 18              # body font-size in px
custom_css = "~/path.css"    # appended after defaults; cascade wins
browser    = "auto"          # "auto" | "firefox --new-window" | ["cmd", "arg"]
                             # The URL is appended as the last arg.
                             # auto = chrome --app= → xdg-open / open
edit       = false           # default for -e (also open nvim). Override with -e / --no-edit.
```

CLI flags override config values.

## Requirements

- Python 3.11+ (for `tomllib`; older Python still works for the plugin, just not the CLI's TOML config).
- Any web browser. If `google-chrome` / `chromium` is on `PATH`, `mdp` uses it with `--app=` for a chromeless window; otherwise it falls back to `xdg-open` (Linux) or `open` (macOS) — your default browser. Override with `browser = "firefox --new-window"` or `browser = ["qutebrowser"]` in the config.
- `xdotool` or `wmctrl` on Linux for closing the synced preview window cleanly (optional, plugin only).

## Layout

```
lua/md-preview/init.lua          -- nvim plugin (server lifecycle, autocmds, IPC)
scripts/_renderer.py             -- shared rendering: venv bootstrap, render_body, build_page
scripts/md-preview-server.py     -- HTTP + WebSocket server for the plugin
scripts/mdp                      -- CLI entrypoint
```

The plugin and CLI share `_renderer.py` so themes, CSS, and markdown rules stay in sync.
