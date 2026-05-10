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

  -- fail_when is a sentinel: tests set it to argv[1] (e.g. "sh") to make
  -- the next stubbed system() call resolve via a real failing shell command,
  -- which sets vim.v.shell_error without writing to it.
  local fail_when

  before_each(function()
    saved = snapshot_fn()
    calls = {}
    notifications = {}
    fail_when = nil

    vim.fn.isdirectory = function() return 1 end
    vim.fn.mkdir = function() end
    vim.fn.expand = function(s) return (s:gsub("^~", "/HOME")) end
    vim.fn.system = function(argv)
      table.insert(calls, argv)
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

  local function had_shell_call_matching(substr)
    for _, argv in ipairs(calls) do
      if type(argv) == "table" and argv[1] == "sh"
         and type(argv[3]) == "string" and argv[3]:find(substr, 1, true) then
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

  it("warns when curl is absent", function()
    vim.fn.executable = function(p)
      if p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    assert(notified_with("mdp binary not found"),
      "expected 'mdp binary not found' notification")
    assert(not had_shell_call_matching("install.sh"),
      "install.sh should not be invoked when curl is missing")
  end)

  it("stays silent when mdp is already on PATH", function()
    vim.fn.executable = function(p)
      if p == "mdp" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    assert(not notified_with("mdp binary not found"),
      "should not warn when mdp is on PATH")
    assert(#calls == 0, "no shell-out should happen when mdp is on PATH")
  end)

  it("runs install.sh via curl|sh when mdp missing and curl available", function()
    vim.fn.executable = function(p)
      if p == "curl" or p == "sh" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local ok, argv = had_shell_call_matching("aldevv/md-preview/main/install.sh")
    assert(ok, "expected `sh -c 'curl … install.sh | sh'` invocation, got " .. vim.inspect(calls))
    assert(argv[2] == "-c", "second arg should be -c; got " .. tostring(argv[2]))
  end)

  it("surfaces install failures via err()", function()
    vim.fn.executable = function(p)
      if p == "curl" or p == "sh" then return 1 end
      return 0
    end
    fail_when = "sh"
    fresh_plugin().install_cli()
    assert(notified_with("install failed"), "expected install failure notification")
  end)
end)
