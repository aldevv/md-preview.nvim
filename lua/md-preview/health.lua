-- :checkhealth md-preview entry point. Neovim's health module renamed
-- the API in 0.10 (start/ok/warn/error/info) and kept the 0.9 names as
-- deprecated aliases (report_*); fall back so we work on either floor.

local h = vim.health
local hstart = h.start or h.report_start
local hok = h.ok or h.report_ok
local hwarn = h.warn or h.report_warn
local herr = h.error or h.report_error
local hinfo = h.info or h.report_info

local M = {}

local function check_dep(name, advice)
  if vim.fn.executable(name) == 1 then
    hok("`" .. name .. "` found on PATH")
    return true
  end
  if advice then
    hwarn("`" .. name .. "` not found on PATH", advice)
  else
    hwarn("`" .. name .. "` not found on PATH")
  end
  return false
end

function M.check()
  hstart("md-preview.nvim")

  if vim.fn.executable("mdp") == 1 then
    hok("`mdp` binary on PATH")
  else
    herr("`mdp` binary not found", {
      "Run `:MdPreviewInstall`, or",
      "`curl -fsSL https://raw.githubusercontent.com/aldevv/md-preview/main/install.sh | sh`",
    })
  end

  check_dep("curl", { "Required by :MdPreviewInstall." })
  check_dep("sh", { "Required by :MdPreviewInstall." })

  local platform = require("md-preview.platform")
  local chrome = platform.find_chrome()
  if chrome then
    hok("Chromium-family browser found: `" .. chrome .. "`")
  else
    hwarn("No google-chrome / chromium / chromium-browser on PATH", {
      "The preview will fall back to xdg-open / open and won't run as `--app=`.",
    })
  end

  local uname = (vim.uv or vim.loop).os_uname()
  hinfo("Platform: " .. uname.sysname)

  if uname.sysname == "Linux" then
    if vim.fn.executable("xdotool") == 1 then
      hok("`xdotool` available (used to close the preview window)")
    elseif vim.fn.executable("wmctrl") == 1 then
      hok("`wmctrl` available (used to close the preview window)")
    else
      hwarn("Neither `xdotool` nor `wmctrl` is on PATH", {
        "M.close() will leave the Chrome --app window open; you'll need to close it manually.",
      })
    end

    if vim.fn.executable("lsof") == 1 then
      hok("`lsof` available (used to clear stale `mdp` servers on cold open)")
    else
      hinfo("`lsof` not found — orphan-server detection on cold open is skipped")
    end

    local wm = platform.detect_wm()
    if wm and platform.AUTO_TILING_WMS[wm] then
      hok("WM `" .. wm .. "` is a known auto-tiler — Chrome will be placed by the WM")
    else
      hinfo("WM `" .. (wm or "unknown") .. "` — Chrome will launch without auto-positioning")
    end

    local wayland = os.getenv("WAYLAND_DISPLAY")
    if wayland and wayland ~= "" then
      hinfo("Wayland session detected (WAYLAND_DISPLAY=" .. wayland .. ")")
      hinfo("xdotool/wmctrl are X11-only; window-close may be a no-op for native-Wayland Chrome")
    end
  elseif uname.sysname == "Darwin" then
    local opts = require("md-preview.state").opts
    hinfo(
      "AppleScript will tile process `" .. (opts.terminal_app or "kitty") .. "` beside Chrome (configurable via the `terminal_app` opt)"
    )
  else
    hwarn("Platform `" .. uname.sysname .. "` is not officially supported", {
      "macOS and Linux are tested. Native Windows is not supported (WSL works).",
    })
  end
end

return M
