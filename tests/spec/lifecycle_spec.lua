local function fresh_plugin()
  package.loaded["md-preview"] = nil
  return require("md-preview")
end

describe("is_alive", function()
  it("returns false when no job has been started", function()
    local m = fresh_plugin()
    m.state.job_id = nil
    assert.is_false(m.is_alive())
  end)

  it("returns true when jobwait reports the job is still running", function()
    local m = fresh_plugin()
    local saved = vim.fn.jobwait
    vim.fn.jobwait = function() return { -1 } end
    m.state.job_id = 42
    local ok = m.is_alive()
    vim.fn.jobwait = saved
    m.state.job_id = nil
    assert.is_true(ok)
  end)

  it("returns false when jobwait reports an exit code", function()
    local m = fresh_plugin()
    local saved = vim.fn.jobwait
    vim.fn.jobwait = function() return { 0 } end
    m.state.job_id = 42
    local ok = m.is_alive()
    vim.fn.jobwait = saved
    m.state.job_id = nil
    assert.is_false(ok)
  end)
end)

describe("M.open argument validation", function()
  it("rejects a non-markdown buffer", function()
    local m = fresh_plugin()
    local saved_expand = vim.fn.expand
    local saved_notify = vim.notify
    local notified
    vim.fn.expand = function(s)
      if s == "%:p" then return "/tmp/not-markdown.txt" end
      return saved_expand(s)
    end
    vim.notify = function(msg) notified = msg end

    m.open("dark")

    vim.fn.expand = saved_expand
    vim.notify = saved_notify
    assert(
      notified and notified:find("Not a markdown file", 1, true),
      "expected 'Not a markdown file' notification, got: " .. tostring(notified)
    )
  end)

  it("errors out when no mdp binary is reachable", function()
    local m = fresh_plugin()
    local saved_expand = vim.fn.expand
    local saved_executable = vim.fn.executable
    local saved_jobstart = vim.fn.jobstart
    local saved_notify = vim.notify
    local saved_system = vim.fn.system

    local notifications = {}
    local jobstart_called = false

    vim.fn.expand = function(s)
      if s == "%:p" then return "/tmp/sample.md" end
      if s == "~/.local/bin" then return "/HOME/.local/bin" end
      return saved_expand(s)
    end
    vim.fn.executable = function() return 0 end
    vim.fn.system = function()
      vim.v.shell_error = 0
      return ""
    end
    vim.fn.jobstart = function()
      jobstart_called = true
      return 1
    end
    vim.notify = function(msg) table.insert(notifications, msg) end

    m.state.job_id = nil
    m.state.platform = "linux"
    m.open("dark")

    vim.fn.expand = saved_expand
    vim.fn.executable = saved_executable
    vim.fn.jobstart = saved_jobstart
    vim.fn.system = saved_system
    vim.notify = saved_notify

    assert(not jobstart_called, "jobstart should not run when mdp is missing")
    local saw_err = false
    for _, n in ipairs(notifications) do
      if type(n) == "string" and n:find("mdp binary not found", 1, true) then saw_err = true end
    end
    assert(saw_err, "expected 'mdp binary not found' notification, got: " .. vim.inspect(notifications))
  end)
end)
