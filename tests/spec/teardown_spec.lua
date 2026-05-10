local function fresh_plugin()
  package.loaded["md-preview"] = nil
  return require("md-preview")
end

describe("M.close teardown", function()
  it("clears job_id, file, and augroup state", function()
    local m = fresh_plugin()
    local saved_jobwait = vim.fn.jobwait
    local saved_jobstop = vim.fn.jobstop
    local saved_chansend = vim.fn.chansend
    local saved_jobstart = vim.fn.jobstart
    local saved_executable = vim.fn.executable
    local saved_system = vim.fn.system
    local saved_notify = vim.notify
    local saved_del = vim.api.nvim_del_augroup_by_id

    vim.fn.jobwait = function() return { -1 } end
    vim.fn.jobstop = function() end
    vim.fn.chansend = function() end
    vim.fn.jobstart = function() return 99 end
    vim.fn.executable = function() return 0 end
    vim.fn.system = function() vim.v.shell_error = 0; return "" end
    vim.notify = function() end
    vim.api.nvim_del_augroup_by_id = function() end

    m.state.job_id = 42
    m.state.file = "/tmp/x.md"
    m.state.augroup = 7
    m.state.platform = "linux"

    m.close()

    assert.is_nil(m.state.job_id, "job_id should be cleared")
    assert.is_nil(m.state.file, "file should be cleared")
    assert.is_nil(m.state.augroup, "augroup should be cleared")

    vim.fn.jobwait = saved_jobwait
    vim.fn.jobstop = saved_jobstop
    vim.fn.chansend = saved_chansend
    vim.fn.jobstart = saved_jobstart
    vim.fn.executable = saved_executable
    vim.fn.system = saved_system
    vim.notify = saved_notify
    vim.api.nvim_del_augroup_by_id = saved_del
  end)

  it("close() with no live job is a safe no-op", function()
    local m = fresh_plugin()
    m.state.job_id = nil
    m.state.file = nil
    m.state.augroup = nil
    m.state.platform = "linux"

    local saved_executable = vim.fn.executable
    local saved_system = vim.fn.system
    local saved_notify = vim.notify
    vim.fn.executable = function() return 0 end
    vim.fn.system = function() return "" end
    vim.notify = function() end

    local ok = pcall(m.close)
    assert.is_true(ok, "close() must not throw when no job is running")

    vim.fn.executable = saved_executable
    vim.fn.system = saved_system
    vim.notify = saved_notify
  end)
end)

describe("ipc.has_pending_timer", function()
  it("is false on a fresh module load", function()
    package.loaded["md-preview.ipc"] = nil
    local ipc = require("md-preview.ipc")
    assert.is_false(ipc.has_pending_timer())
  end)

  it("is false after cancel_debounce", function()
    local ipc = require("md-preview.ipc")
    ipc.cancel_debounce()
    assert.is_false(ipc.has_pending_timer())
  end)
end)

describe("autocmds.register", function()
  it("creates an augroup and four autocmds in it", function()
    package.loaded["md-preview.autocmds"] = nil
    package.loaded["md-preview.state"] = nil
    local autocmds = require("md-preview.autocmds")
    local store    = require("md-preview.state")

    -- Stub plugin callbacks; we only need the autocmds wired, not fired.
    local plugin = {
      on_save         = function() end,
      on_cursor_moved = function() end,
      close           = function() end,
    }

    autocmds.register(plugin)

    assert.is_truthy(store.state.augroup, "augroup id should be set")
    local entries = vim.api.nvim_get_autocmds({ group = store.state.augroup })
    local events = {}
    for _, e in ipairs(entries) do events[e.event] = true end
    assert.is_true(events.BufWritePost, "BufWritePost autocmd missing")
    assert.is_true(events.CursorMoved,  "CursorMoved autocmd missing")
    assert.is_true(events.BufWipeout,   "BufWipeout autocmd missing")
    assert.is_true(events.VimLeavePre,  "VimLeavePre autocmd missing")

    pcall(vim.api.nvim_del_augroup_by_id, store.state.augroup)
    store.state.augroup = nil
  end)

  it("re-registering deletes the previous augroup", function()
    local autocmds = require("md-preview.autocmds")
    local store    = require("md-preview.state")
    local plugin = {
      on_save         = function() end,
      on_cursor_moved = function() end,
      close           = function() end,
    }

    autocmds.register(plugin)
    local first = store.state.augroup
    autocmds.register(plugin)
    local second = store.state.augroup

    assert.is_truthy(first)
    assert.is_truthy(second)
    -- The first group id must be invalid now (its autocmds are cleared).
    local ok = pcall(vim.api.nvim_get_autocmds, { group = first })
    assert.is_false(ok, "first augroup id should be invalid after re-register")

    pcall(vim.api.nvim_del_augroup_by_id, store.state.augroup)
    store.state.augroup = nil
  end)
end)
