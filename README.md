# md-preview.nvim

Scroll-synced markdown preview for Neovim, plus a standalone `mdp` CLI for one-shot rendering — both backed by [goldmark](https://github.com/yuin/goldmark) and shipped as a single Go binary.

## Features

- Live preview that follows your cursor and re-renders on save (Neovim plugin).
- Standalone `mdp` CLI: `mdp file.md` opens a static rendered HTML in Chrome `--app=` (or your browser of choice).
- Single static binary — no Python, no pip, no venv.
- Vim-style scroll bindings in the rendered page: `j`/`k`, `h`/`l`, `d`/`u` (half-page), `g`/`G` (top/bottom).
- Dark / light themes, GitHub-flavored markdown (tables, strikethrough, autolink, task lists), syntax highlighting via highlight.js.
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

On `setup()`, the plugin builds the `mdp` binary (`go build`) into the plugin dir if it isn't there yet, then symlinks `~/.local/bin/mdp` to it. Requires Go on PATH for the build step; alternatively, install the binary first via the one-liner below.

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

One-liner — uses `go install` if Go is on PATH, otherwise downloads a prebuilt release binary:

```sh
curl -fsSL https://raw.githubusercontent.com/aldevv/md-preview.nvim/main/install.sh | sh
```

Override the prefix with `PREFIX=...` (default `$HOME/.local`):

```sh
PREFIX=/usr/local sh install.sh   # system-wide
```

Or directly with Go:

```sh
go install github.com/aldevv/md-preview/cmd/mdp@latest
```

The Neovim plugin builds the binary on `setup()` (when Go is available), so plugin users typically don't need either of the above.

## CLI usage

```sh
mdp                        # fzf-pick a .md from cwd, then preview
mdp README.md              # render + open in browser
mdp -e README.md           # preview AND open the file in nvim
mdp -e                     # fzf-pick, preview, and edit
mdp -t light README.md     # light theme
mdp -p README.md           # print HTML path, don't open browser
```

If `fzf` is not installed and you run `mdp` with no file argument, it prints usage plus a note about installing fzf.

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

- Go 1.22+ (only for building from source; users on releases don't need it).
- Any web browser. If `google-chrome` / `chromium` is on `PATH`, `mdp` uses it with `--app=` for a chromeless window; otherwise it falls back to `xdg-open` (Linux) or `open` (macOS) — your default browser. Override with `browser = "firefox --new-window"` or `browser = ["qutebrowser"]` in the config.
- `xdotool` or `wmctrl` on Linux for closing the synced preview window cleanly (optional, plugin only).

## Layout

```
cmd/mdp/main.go              -- CLI entrypoint + `mdp serve` subcommand
internal/render              -- markdown → HTML body + page template
internal/server              -- HTTP + WebSocket server for the plugin
internal/config              -- TOML config, browser detection, fzf picker
lua/md-preview/init.lua      -- nvim plugin (server lifecycle, autocmds, IPC)
```

The plugin spawns the server via `mdp serve <file> <port> <theme>` and communicates over JSON-on-stdin.
