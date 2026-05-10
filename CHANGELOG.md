# Changelog

All notable changes to `md-preview.nvim` are documented here. The format
loosely follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/);
the project is pre-1.0 so the API may change between minor versions.

## Unreleased

### Added
- `doc/md-preview.txt` — vimdoc reference. `:help md-preview`,
  `:help :MdPreviewInstall`, `:help md-preview-setup` all resolve.
- `:checkhealth md-preview` provider (`lua/md-preview/health.lua`) —
  verifies `mdp` binary, `curl`/`sh`, Chromium-family browser,
  `xdotool`/`wmctrl` (Linux), `lsof` (Linux), surfaces detected WM and
  Wayland status.
- GitHub Actions CI (`.github/workflows/ci.yml`) — runs `make test-lua`
  against Neovim `v0.9.5`, `v0.10.2`, and `nightly` on every push to
  `main` and every PR.
- `port` setup opt — was hardcoded at `9753`; now configurable so two
  concurrent Neovim sessions can run on different ports.
- `terminal_app` setup opt (macOS) — was hardcoded as `"kitty"` in the
  AppleScript that tiles the terminal beside Chrome; now defaults to
  `"kitty"` but accepts any process name (alacritty, wezterm, iTerm2,
  Terminal, Ghostty, …). The terminal-resize block is wrapped in
  `try`/`on error` so non-matching terminals just skip the resize.
- `:MdPreviewInstall` is the recommended `build` value in plugin specs
  (still works as a raw `curl … | sh`, just better single-source).
- `ipc.has_pending_timer()` predicate so tests / external callers can
  observe whether a debounce is in flight without poking module-private
  state.
- Native Windows is now rejected with a clear `notify.warn` at `setup()`
  time instead of silently falling through to the Linux branch.
- Wayland warning when neither `xdotool` nor `wmctrl` is available — the
  preview window can't be closed automatically there.

### Changed
- `setup()` is idempotent: opts can be merged on subsequent calls but
  side effects (platform detection, keymap registration, user-command
  registration, `mdp` PATH check) run only once. Lazy.nvim hot-reloads
  no longer stack duplicate keymap bindings.
- Top-level `require()` fanout in `init.lua` reduced. `browser`,
  `autocmds`, `install`, and `keymaps` are lazy-required behind their
  callsites so users who never preview don't pay parse + execute cost
  on every Neovim launch.
- `M.on_cursor_moved` short-circuits when CursorMoved fires in some
  other `*.md` buffer (the autocmd pattern is glob, not buffer-local),
  avoiding the `vim.fn.jobwait` cost on non-previewed buffers.
- `server.clear_stale` no longer uses `vim.wait(500, …)`. The subsequent
  `poll_ready` TCP probe already confirms the port is free; the extra
  blocking wait was redundant. Cold `M.open` is faster.
- `server.clear_stale` now uses `ps -o comm=` (portable across Linux
  and macOS) and matches the executable basename `mdp` exactly, so
  `mdpfoobar` and `less mdp_serve.txt` no longer false-positive. The
  old `mdp%s+serve` regex spec (`tests/spec/serve_pattern_spec.lua`) is
  removed alongside.
- VimLeavePre / BufWipeout autocmds are registered immediately after
  `jobstart` succeeds, not after `poll_ready` returns. Quitting Neovim
  during the (up to ~10s) server-start window now triggers cleanup
  correctly.
- `ipc.poll_ready`'s `sock:close()` is now guarded with `is_closing()`
  so a stale connect callback after a retry doesn't throw.
- `autocmds.register`'s `nvim_del_augroup_by_id` is `pcall`-wrapped to
  match `init.lua:M.close`, so a stale group id doesn't abort
  registration.

### Fixed
- `tests/smoke.lua` no longer references the (removed) `state.debounce_timer`
  field; it now uses `ipc.has_pending_timer()`. The cursor-debounce step
  was silently a no-op after the recent module split — now actually exercises
  the timer race.
- `README.md` no longer claims the `mdp` binary is auto-installed via
  `go install`; that path was dropped in commit `49f3eea`. The Requirements
  section now reflects the `install.sh` flow and declares the Neovim ≥ 0.9
  floor explicitly.

### Tests
- New `tests/spec/teardown_spec.lua` covers `M.close` state cleanup,
  `ipc.has_pending_timer`, and `autocmds.register` augroup lifecycle.
