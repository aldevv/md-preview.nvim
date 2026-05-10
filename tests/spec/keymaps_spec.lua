local function fresh_plugin()
  package.loaded["md-preview"] = nil
  return require("md-preview")
end

-- spy_keymap_set replaces vim.keymap.set with a recorder. Returns a
-- restore function and a list that gets appended to on every call.
local function spy_keymap_set()
  local saved = vim.keymap.set
  local calls = {}
  vim.keymap.set = function(mode, lhs, rhs, opts) table.insert(calls, { mode = mode, lhs = lhs, rhs = rhs, opts = opts }) end
  return function() vim.keymap.set = saved end, calls
end

-- silence_setup mutes setup()'s "mdp not found" WARN and the user_command
-- registration (which otherwise prints in test output). Returns a restore.
local function silence_setup()
  local saved_notify = vim.notify
  local saved_cmd = vim.api.nvim_create_user_command
  vim.notify = function() end
  vim.api.nvim_create_user_command = function() end
  return function()
    vim.notify = saved_notify
    vim.api.nvim_create_user_command = saved_cmd
  end
end

describe("setup() leader keymaps", function()
  it("registers the three default mappings when keymaps is unset", function()
    local m = fresh_plugin()
    local restore_silence = silence_setup()
    local restore_spy, calls = spy_keymap_set()

    m.setup()

    restore_spy()
    restore_silence()

    assert.are.equal(3, #calls)
    local lhs = {}
    for _, c in ipairs(calls) do
      lhs[c.lhs] = true
    end
    assert.is_true(lhs["<leader>mv"])
    assert.is_true(lhs["<leader>mV"])
    assert.is_true(lhs["<leader>mq"])
  end)

  it("registers no keymaps when keymaps = false", function()
    local m = fresh_plugin()
    local restore_silence = silence_setup()
    local restore_spy, calls = spy_keymap_set()

    m.setup({ keymaps = false })

    restore_spy()
    restore_silence()
    assert.are.equal(0, #calls)
  end)

  it("merges a partial table with defaults", function()
    local m = fresh_plugin()
    local restore_silence = silence_setup()
    local restore_spy, calls = spy_keymap_set()

    m.setup({ keymaps = { open_dark = "<leader>op" } })

    restore_spy()
    restore_silence()

    local lhs = {}
    for _, c in ipairs(calls) do
      lhs[c.lhs] = true
    end
    assert.is_true(lhs["<leader>op"], "custom open_dark should be registered")
    assert.is_true(lhs["<leader>mV"], "default open_light should remain")
    assert.is_true(lhs["<leader>mq"], "default close should remain")
    assert.is_nil(lhs["<leader>mv"], "old default open_dark should not be registered")
  end)

  it("skips a single binding when its value is false", function()
    local m = fresh_plugin()
    local restore_silence = silence_setup()
    local restore_spy, calls = spy_keymap_set()

    m.setup({ keymaps = { close = false } })

    restore_spy()
    restore_silence()

    local lhs = {}
    for _, c in ipairs(calls) do
      lhs[c.lhs] = true
    end
    assert.is_true(lhs["<leader>mv"])
    assert.is_true(lhs["<leader>mV"])
    assert.is_nil(lhs["<leader>mq"], "close should be skipped")
  end)
end)
