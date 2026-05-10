# md-preview.nvim

Scroll-synced markdown preview for Neovim. Re-renders on save, follows your cursor, opens in Chrome `--app=` (or your browser of choice).

The renderer/server lives in a separate repo: [aldevv/md-preview](https://github.com/aldevv/md-preview). This plugin spawns the `mdp` binary and talks to it over stdin.

## Install (lazy.nvim)

```lua
{
  "aldevv/md-preview.nvim",
  ft    = { "markdown" },
  build = ":MdPreviewInstall",
  config = function()
    require("md-preview").setup()
  end,
}
```

`build` runs once at install/update time. `:MdPreviewInstall` is the user command the plugin registers in `setup()`; it shells out to the same `install.sh` as the manual one-liner below, dropping the prebuilt `mdp` binary into `$HOME/.local/bin` (override with `PREFIX=...`). The raw-curl form (`build = "curl -fsSL https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh | sh"`) also works if you'd rather not rely on the user command.

If you skip `build`, `setup()` warns that `mdp` isn't on `PATH` and prompts you to run `:MdPreviewInstall`. You can also install manually:

```sh
curl -fsSL https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh | sh
```

(`~/.local/bin` must be on your `PATH` — most distros pre-add it; otherwise add `export PATH="$HOME/.local/bin:$PATH"` to your shell rc.)

## Usage

```lua
require("md-preview").open("dark")   -- or "light"
require("md-preview").close()
```

While open, `BufWritePost` re-renders, `CursorMoved` syncs scroll (debounced), `BufWipeout` of the previewed file closes the server.

## Configuration

`setup()` accepts the following options (all optional):

```lua
require("md-preview").setup({
  auto_position = true,    -- tile terminal + browser side-by-side (macOS / known WMs)
  keymaps       = true,    -- true = defaults below | false = none | table = overrides
  colemak       = false,   -- swap in-page nav keys j/k/l → n/e/i (h, d/u, g/G unchanged)
  port          = 9753,    -- port the `mdp serve` HTTP/WS server binds to
  terminal_app  = "kitty", -- macOS only: AppleScript process name to tile beside Chrome
})
```

Default keymaps registered on `setup()`:

| Key            | Action       |
| -------------- | ------------ |
| `<leader>mv`   | open (dark)  |
| `<leader>mV`   | open (light) |
| `<leader>mq`   | close        |

Override individual entries (missing keys keep their defaults; set one to `false` to skip just that binding):

```lua
require("md-preview").setup({
  keymaps = {
    open_dark  = "<leader>op",
    open_light = "<leader>oP",
    close      = false,        -- don't bind close at all
  },
})
```

Disable all keymap registration:

```lua
require("md-preview").setup({ keymaps = false })
```

## CLI config

The `mdp` binary reads `~/.config/md-preview/config.toml`. See the [md-preview README](https://github.com/aldevv/md-preview#config----configmd-previewconfigtoml) for the full reference. The plugin's `colemak = true` opt forces colemak mode via `MDP_COLEMAK=1` regardless of the config file.

## Requirements

- **Neovim ≥ 0.9** (uses `vim.uv or vim.loop`, `vim.json.encode`, `vim.api.nvim_create_augroup{ clear = true }`, `vim.keymap.set`).
- The `mdp` binary on `PATH` — fetched as a prebuilt binary by [`install.sh`](https://github.com/aldevv/md-preview/blob/main/install.sh) (no Go toolchain required). Run `:MdPreviewInstall` from inside Neovim, or wire it as the lazy.nvim `build` step shown above.
- A Chromium-family browser for the chromeless `--app=` window. On Linux, `mdp` looks for `google-chrome` / `chromium` / `chromium-browser` and falls back to `xdg-open` if none are on `PATH`.
- `xdotool` or `wmctrl` on Linux for closing the synced preview window cleanly (optional). On a pure Wayland session where neither tool can see the window, you'll get a warning and need to close it manually.
- **Native Windows is not supported.** WSL works (it's Linux from Neovim's perspective).

## Tests

```sh
make test-lua
```

Requires `nvim` on PATH; plenary is auto-cloned into `tests/site/pack/`.
