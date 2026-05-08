local function snapshot_fn()
  return {
    executable = vim.fn.executable,
    isdirectory = vim.fn.isdirectory,
    mkdir = vim.fn.mkdir,
    system = vim.fn.system,
    expand = vim.fn.expand,
    resolve = vim.fn.resolve,
    notify = vim.notify,
  }
end

local function restore_fn(saved)
  vim.fn.executable = saved.executable
  vim.fn.isdirectory = saved.isdirectory
  vim.fn.mkdir = saved.mkdir
  vim.fn.system = saved.system
  vim.fn.expand = saved.expand
  vim.fn.resolve = saved.resolve
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

  -- shell_error_for is a sentinel: tests set it to argv[1] (e.g. "ln")
  -- to make the next stubbed system() call resolve via a real failing
  -- shell command, which sets vim.v.shell_error without writing to it.
  local fail_when

  before_each(function()
    saved = snapshot_fn()
    calls = { system = {} }
    notifications = {}
    fail_when = nil

    vim.fn.isdirectory = function() return 1 end
    vim.fn.mkdir = function() end
    vim.fn.expand = function(s) return (s:gsub("^~", "/HOME")) end
    vim.fn.resolve = function(p) return p end
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

  it("warns when binary, go, and PATH-mdp are all absent", function()
    vim.fn.executable = function() return 0 end
    fresh_plugin().install_cli()
    assert(notified_with("mdp binary not found"),
      "expected 'mdp binary not found' notification")
    assert(not had_call("go"), "go build should not be invoked")
    assert(not had_call("ln"), "ln should not be invoked")
  end)

  it("stays silent when binary missing but mdp is on PATH", function()
    vim.fn.executable = function(p)
      if p == "mdp" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    assert(not notified_with("mdp binary not found"),
      "should not warn when mdp is on PATH")
    assert(not had_call("go"), "go build should not be invoked")
  end)

  it("invokes go build when go is available and binary missing", function()
    vim.fn.executable = function(p)
      if p == "go" then return 1 end
      return 0
    end
    fresh_plugin().install_cli()
    local ok, argv = had_call("go")
    assert(ok, "go build should be invoked")
    assert(argv[2] == "build", "second arg should be 'build'")
    local saw_C, saw_o, saw_pkg = false, false, false
    for i = 3, #argv do
      if argv[i] == "-C" then saw_C = true end
      if argv[i] == "-o" then saw_o = true end
      if argv[i] == "./cmd/mdp" then saw_pkg = true end
    end
    assert(saw_C, "go build missing -C flag")
    assert(saw_o, "go build missing -o flag")
    assert(saw_pkg, "go build missing ./cmd/mdp package")
  end)

  it("symlinks binary when it exists and the link is missing or stale", function()
    vim.fn.executable = function() return 1 end
    vim.fn.resolve = function() return "/somewhere/else" end
    fresh_plugin().install_cli()
    local ok, argv = had_call("ln")
    assert(ok, "ln -sf should be invoked")
    assert(argv[2] == "-sf", "ln should use -sf")
  end)

  it("skips ln when symlink already resolves to the binary", function()
    vim.fn.executable = function() return 1 end
    local m = fresh_plugin()
    local src = debug.getinfo(m.install_cli, "S").source:sub(2)
    local target = vim.fn.fnamemodify(src, ":h:h:h") .. "/mdp"
    vim.fn.resolve = function() return target end
    m.install_cli()
    assert(not had_call("ln"), "ln should not run when symlink already correct")
  end)

  it("surfaces ln -sf failures via err()", function()
    vim.fn.executable = function() return 1 end
    vim.fn.resolve = function() return "/somewhere/else" end
    fail_when = "ln"
    fresh_plugin().install_cli()
    assert(notified_with("ln -sf"), "expected ln -sf failure notification")
  end)

  it("surfaces go build failures via err()", function()
    vim.fn.executable = function(p)
      if p == "go" then return 1 end
      return 0
    end
    fail_when = "go"
    fresh_plugin().install_cli()
    assert(notified_with("go build failed"), "expected go build failure notification")
  end)
end)
