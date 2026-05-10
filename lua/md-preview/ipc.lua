local notify   = require("md-preview.notify")
local platform = require("md-preview.platform")
local server   = require("md-preview.server")
local store    = require("md-preview.state")

local uv = platform.uv
local M = {}

local current_timer = nil
local last_scroll_line = nil

-- Both the cancellation path and the vim.schedule_wrap'd callback can race
-- to close the same uv handle: a timer fires, libuv queues its cb, and
-- before the cb runs another CursorMoved cancels and closes the handle.
-- When the queued cb finally runs, calling :close() again throws "handle
-- is already closing". is_closing() makes the close idempotent.
local function close_handle(h)
  if h and not h:is_closing() then
    pcall(function() h:stop() end)
    h:close()
  end
end

function M.has_pending_timer() return current_timer ~= nil end

function M.send(msg)
  if not server.is_alive() then return end
  -- Any non-scroll message (render, quit) invalidates the dedupe baseline.
  if msg.type ~= "scroll" then last_scroll_line = nil end
  vim.fn.chansend(store.state.job_id, vim.json.encode(msg) .. "\n")
end

function M.cancel_debounce()
  close_handle(current_timer)
  current_timer = nil
  last_scroll_line = nil
end

function M.debounce_scroll(get_row)
  close_handle(current_timer)
  local timer = uv.new_timer()
  current_timer = timer
  timer:start(50, 0, vim.schedule_wrap(function()
    -- A fresher CursorMoved may have replaced us; the cancellation path
    -- already closed our handle.
    if current_timer ~= timer then return end
    current_timer = nil
    close_handle(timer)
    if not server.is_alive() then return end
    local row = get_row()
    if row == last_scroll_line then return end
    last_scroll_line = row
    M.send({ type = "scroll", line = row })
  end))
end

-- TCP probe rather than shelling out to curl every 50ms — same readiness
-- signal, no fork+exec on each retry.
function M.poll_ready(port, on_ready, retries)
  retries = retries or 0
  if retries > 200 then
    notify.err("Server did not start on port " .. port)
    return
  end
  local sock = uv.new_tcp()
  sock:connect("127.0.0.1", port, vim.schedule_wrap(function(connect_err)
    -- The connect callback can fire after a stale retry already closed us.
    close_handle(sock)
    if not connect_err then
      on_ready()
    else
      vim.defer_fn(function() M.poll_ready(port, on_ready, retries + 1) end, 50)
    end
  end))
end

return M
