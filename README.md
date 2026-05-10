# md-preview.nvim

Scroll-synced markdown preview for Neovim. Re-renders on save, follows your cursor, opens in Chrome `--app=` (or your browser of choice).

The renderer/server lives in a separate repo: [aldevv/md-preview](https://github.com/aldevv/md-preview). This plugin spawns the `mdp` binary and talks to it over stdin.

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

On `setup()`, the plugin checks for `mdp` on PATH. If it's missing and `curl` is available, it runs the standalone install script — which downloads a prebuilt binary into `~/.local/bin/mdp` (no Go toolchain required). You can also install manually:

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
  auto_position = true,   -- tile terminal + browser side-by-side (macOS / known WMs)
  keymaps       = true,   -- true = defaults below | false = none | table = overrides
  colemak       = false,  -- swap in-page nav keys j/k/l → n/e/i (h, d/u, g/G unchanged)
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

- The `mdp` binary on `PATH` — auto-installed via `go install` if Go is available, otherwise install via the [one-liner](https://github.com/aldevv/md-preview#install).
- Any web browser. If `google-chrome` / `chromium` is on `PATH`, `mdp` opens it with `--app=` for a chromeless window; otherwise it falls back to `xdg-open` (Linux) or `open` (macOS).
- `xdotool` or `wmctrl` on Linux for closing the synced preview window cleanly (optional).

## Tests

```sh
make test-lua
```

Requires `nvim` on PATH; plenary is auto-cloned into `tests/site/pack/`.
