local function fresh_plugin()
  package.loaded["md-preview"] = nil
  return require("md-preview")
end

-- spy_keymap_set replaces vim.keymap.set with a recorder. Returns a
-- restore function and a list that gets appended to on every call.
local function spy_keymap_set()
  local saved = vim.keymap.set
  local calls = {}
  vim.keymap.set = function(mode, lhs, rhs, opts)
    table.insert(calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts })
  end
  return function() vim.keymap.set = saved end, calls
end

-- stub_install_cli prevents setup() from touching the filesystem / go.
local function stub_install_cli(m)
  local saved = m.install_cli
  m.install_cli = function() end
  return function() m.install_cli = saved end
end

describe("setup() leader keymaps", function()
  it("registers the three default mappings when keymaps is unset", function()
    local m = fresh_plugin()
    local restore_install = stub_install_cli(m)
    local restore_spy, calls = spy_keymap_set()

    m.setup()

    restore_spy()
    restore_install()

    assert.are.equal(3, #calls)
    local lhs = {}
    for _, c in ipairs(calls) do lhs[c.lhs] = true end
    assert.is_true(lhs["<leader>mv"])
    assert.is_true(lhs["<leader>mV"])
    assert.is_true(lhs["<leader>mq"])
  end)

  it("registers no keymaps when keymaps = false", function()
    local m = fresh_plugin()
    local restore_install = stub_install_cli(m)
    local restore_spy, calls = spy_keymap_set()

    m.setup({ keymaps = false })

    restore_spy()
    restore_install()
    assert.are.equal(0, #calls)
  end)

  it("merges a partial table with defaults", function()
    local m = fresh_plugin()
    local restore_install = stub_install_cli(m)
    local restore_spy, calls = spy_keymap_set()

    m.setup({ keymaps = { open_dark = "<leader>op" } })

    restore_spy()
    restore_install()

    local lhs = {}
    for _, c in ipairs(calls) do lhs[c.lhs] = true end
    assert.is_true(lhs["<leader>op"], "custom open_dark should be registered")
    assert.is_true(lhs["<leader>mV"], "default open_light should remain")
    assert.is_true(lhs["<leader>mq"], "default close should remain")
    assert.is_nil(lhs["<leader>mv"], "old default open_dark should not be registered")
  end)

  it("skips a single binding when its value is false", function()
    local m = fresh_plugin()
    local restore_install = stub_install_cli(m)
    local restore_spy, calls = spy_keymap_set()

    m.setup({ keymaps = { close = false } })

    restore_spy()
    restore_install()

    local lhs = {}
    for _, c in ipairs(calls) do lhs[c.lhs] = true end
    assert.is_true(lhs["<leader>mv"])
    assert.is_true(lhs["<leader>mV"])
    assert.is_nil(lhs["<leader>mq"], "close should be skipped")
  end)
end)
