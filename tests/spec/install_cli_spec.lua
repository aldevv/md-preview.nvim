local function snapshot_fn()
  return {
    executable = vim.fn.executable,
    isdirectory = vim.fn.isdirectory,
    mkdir = vim.fn.mkdir,
    system = vim.fn.system,
    expand = vim.fn.expand,
    notify = vim.notify,
  }
end

local function restore_fn(saved)
  vim.fn.executable = saved.executable
  vim.fn.isdirectory = saved.isdirectory
  vim.fn.mkdir = saved.mkdir
  vim.fn.system = saved.system
  vim.fn.expand = saved.expand
  vim.notify = saved.notify
end

local function fresh_plugin()
  package.loaded["md-preview"] = nil
  return require("md-preview")
end

describe("install_cli", function()
  local saved
  local calls
  local notifications

  -- fail_when is a sentinel: tests set it to argv[1] (e.g. "env") to make
  -- the next stubbed system() call resolve via a real failing shell command,
  -- which sets vim.v.shell_error without writing to it.
  local fail_when

  before_each(function()
    saved = snapshot_fn()
    calls = { system = {} }
    notifications = {}
    fail_when = nil

    vim.fn.isdirectory = function() return 1 end
    vim.fn.mkdir = function() end
    vim.fn.expand = function(s) return (s:gsub("^~", "/HOME")) end
    vim.fn.system = function(argv)
      table.insert(calls.system, argv)
      if type(argv) == "table" and fail_when == argv[1] then
        return saved.system("false")
      end
      return saved.system("true")
    end
    vim.notify = function(msg, level)
      table.insert(notifications, { msg = msg, level = level })
    end
  end)

  after_each(function()
    restore_fn(saved)
  end)

  local function had_call(cmd)
    for _, argv in ipairs(calls.system) do
      if type(argv) == "table" and argv[1] == cmd then
        return true, argv
      end
    end
    return false
  end

  local function notified_with(substr)
    for _, n in ipairs(notifications) do
      if type(n.msg) == "string" and n.msg:find(substr, 1, true) then
        return true
      end
    end
    return false
  end

  it("warns when mdp and go are both absent", function()
    vim.fn.executable = function() return 0 end
    fresh_plugin().install_cli()
    assert(notified_with("mdp binary not found"),
      "expected 'mdp binary not found' notification")
    assert(not had_call("env"), "go install should not be invoked")
  end)

  it("stays silent when mdp is already on PATH", function()
    vim.fn.executable = function(p)
      if p == "mdp" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    assert(not notified_with("mdp binary not found"),
      "should not warn when mdp is on PATH")
    assert(not had_call("env"), "go install should not be invoked when mdp on PATH")
  end)

  it("runs `go install` with GOBIN when mdp missing and go available", function()
    vim.fn.executable = function(p)
      if p == "go" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local ok, argv = had_call("env")
    assert(ok, "env GOBIN=... go install should be invoked")
    -- Expected shape:
    --   { "env", "GOBIN=/HOME/.local/bin", "go", "install",
    --     "github.com/aldevv/md-preview/cmd/mdp@latest" }
    assert(argv[2] and argv[2]:match("^GOBIN="),
      "second arg should set GOBIN; got " .. tostring(argv[2]))
    assert(argv[3] == "go",  "third arg should be 'go'")
    assert(argv[4] == "install", "fourth arg should be 'install'")
    assert(argv[5] == "github.com/aldevv/md-preview/cmd/mdp@latest",
      "fifth arg should be the module path; got " .. tostring(argv[5]))
  end)

  it("surfaces go install failures via err()", function()
    vim.fn.executable = function(p)
      if p == "go" then return 1 end
      return 0
    end
    fail_when = "env"
    fresh_plugin().install_cli()
    assert(notified_with("go install failed"), "expected go install failure notification")
  end)
end)
