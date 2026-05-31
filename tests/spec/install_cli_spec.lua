local function snapshot_fn()
  return {
    executable = vim.fn.executable,
    jobstart = vim.fn.jobstart,
    system = vim.fn.system,
    notify = vim.notify,
    shell_error = vim.v.shell_error,
  }
end

local function restore_fn(saved)
  vim.fn.executable = saved.executable
  vim.fn.jobstart = saved.jobstart
  vim.fn.system = saved.system
  vim.notify = saved.notify
end

local function fresh_plugin()
  package.loaded["md-preview"] = nil
  return require("md-preview")
end

describe("install_cli", function()
  local saved
  local jobstart_calls
  local notifications

  before_each(function()
    saved = snapshot_fn()
    jobstart_calls = {}
    notifications = {}

    -- Default jobstart stub: record the call and return a fake non-zero
    -- channel id so install_cli treats it as successfully scheduled. The
    -- on_exit / on_stderr callbacks are NOT auto-fired here — tests that
    -- want to simulate completion invoke them through the captured opts.
    vim.fn.jobstart = function(argv, opts)
      table.insert(jobstart_calls, { argv = argv, opts = opts })
      return 1
    end
    vim.notify = function(msg, level) table.insert(notifications, { msg = msg, level = level }) end
  end)

  after_each(function() restore_fn(saved) end)

  local function had_jobstart_matching(substr)
    for _, call in ipairs(jobstart_calls) do
      local argv = call.argv
      if type(argv) == "table" and argv[1] == "sh" and type(argv[3]) == "string" and argv[3]:find(substr, 1, true) then
        return true, call
      end
    end
    return false
  end

  local function notified_with(substr)
    for _, n in ipairs(notifications) do
      if type(n.msg) == "string" and n.msg:find(substr, 1, true) then return true end
    end
    return false
  end

  it("warns when curl is absent", function()
    vim.fn.executable = function(p)
      if p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    assert(notified_with("mdp binary not found"), "expected 'mdp binary not found' notification")
    assert(#jobstart_calls == 0, "jobstart should not be invoked when curl is missing")
  end)

  it("stays silent when the in-tree mdp matches the pinned version", function()
    local paths = require("md-preview.paths")
    local install = require("md-preview.install")
    local in_tree = paths.mdp_bin()
    local pinned = install.pinned_version() or "v0.0.0"
    vim.fn.executable = function(p)
      if p == in_tree then return 1 end
      return 0
    end
    vim.fn.system = function(argv)
      if type(argv) == "table" and argv[1] == in_tree and argv[2] == "version" then return pinned end
      return ""
    end
    fresh_plugin().install_cli()
    assert(not notified_with("mdp binary not found"), "should not warn when in-tree mdp matches pin")
    assert(#jobstart_calls == 0, "no jobstart should happen when in-tree mdp matches pin")
  end)

  it("re-installs when the in-tree mdp is at a different version than the pin", function()
    local paths = require("md-preview.paths")
    local in_tree = paths.mdp_bin()
    vim.fn.executable = function(p)
      if p == in_tree or p == "curl" or p == "sh" then return 1 end
      return 0
    end
    vim.fn.system = function() return "v0.0.1-stale" end
    fresh_plugin().install_cli()
    local ok, call = had_jobstart_matching("aldevv/md-preview/main/install.sh")
    assert(ok, "expected jobstart when in-tree mdp version does not match pin")
    assert(call.argv[3]:find("MDP_VERSION=", 1, true), "expected MDP_VERSION to be passed to install.sh")
  end)

  it("re-installs even when mdp is on PATH (we want the in-tree copy)", function()
    vim.fn.executable = function(p)
      if p == "mdp" or p == "curl" or p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local ok = had_jobstart_matching("aldevv/md-preview/main/install.sh")
    assert(ok, "expected jobstart even when mdp is on PATH, got " .. vim.inspect(jobstart_calls))
  end)

  it("schedules install.sh via jobstart when mdp missing and curl available", function()
    vim.fn.executable = function(p)
      if p == "curl" or p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local ok, call = had_jobstart_matching("aldevv/md-preview/main/install.sh")
    assert(ok, "expected jobstart with curl|sh invocation, got " .. vim.inspect(jobstart_calls))
    assert(call.argv[2] == "-c", "second arg should be -c; got " .. tostring(call.argv[2]))
    assert(type(call.opts) == "table", "expected opts table for jobstart")
    assert(type(call.opts.on_exit) == "function", "expected on_exit callback")
    assert(type(call.opts.on_stderr) == "function", "expected on_stderr callback")
  end)

  it("notifies success on exit code 0", function()
    vim.fn.executable = function(p)
      if p == "curl" or p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local _, call = had_jobstart_matching("aldevv/md-preview/main/install.sh")
    call.opts.on_exit(0, 0)
    assert(notified_with("mdp installed"), "expected success notification after on_exit(0)")
  end)

  it("surfaces install failures via err() in on_exit", function()
    vim.fn.executable = function(p)
      if p == "curl" or p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local _, call = had_jobstart_matching("aldevv/md-preview/main/install.sh")
    call.opts.on_stderr(0, { "curl: (6) Could not resolve host" })
    call.opts.on_exit(0, 7)
    assert(notified_with("install failed"), "expected install failure notification")
    assert(notified_with("Could not resolve host"), "expected stderr to be surfaced in failure notification")
  end)

  it("surfaces jobstart scheduling failure (return <= 0)", function()
    vim.fn.executable = function(p)
      if p == "curl" or p == "sh" then return 1 end
      return 0
    end
    vim.fn.jobstart = function(argv, opts)
      table.insert(jobstart_calls, { argv = argv, opts = opts })
      return -1
    end
    fresh_plugin().install_cli()
    assert(notified_with("install failed: jobstart returned -1"), "expected jobstart failure notification")
  end)
end)
