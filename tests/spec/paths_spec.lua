local function snapshot_fn()
  return { executable = vim.fn.executable }
end

local function restore_fn(saved)
  vim.fn.executable = saved.executable
end

describe("paths.resolve_mdp", function()
  local saved
  local paths
  local store

  before_each(function()
    saved = snapshot_fn()
    package.loaded["md-preview.paths"] = nil
    package.loaded["md-preview.state"] = nil
    paths = require("md-preview.paths")
    store = require("md-preview.state")
  end)

  after_each(function()
    restore_fn(saved)
    store.opts.prefer_global_mdp = false
  end)

  it("defaults to the in-tree binary when both are available", function()
    local in_tree = paths.mdp_bin()
    vim.fn.executable = function(p)
      if p == in_tree or p == "mdp" then return 1 end
      return 0
    end
    assert(paths.resolve_mdp() == in_tree, "expected in-tree mdp by default")
  end)

  it("prefers PATH mdp when prefer_global_mdp is true", function()
    local in_tree = paths.mdp_bin()
    store.opts.prefer_global_mdp = true
    vim.fn.executable = function(p)
      if p == in_tree or p == "mdp" then return 1 end
      return 0
    end
    assert(paths.resolve_mdp() == "mdp", "expected PATH mdp when prefer_global_mdp is true")
  end)

  it("falls back to in-tree when PATH mdp is missing and prefer_global_mdp is true", function()
    local in_tree = paths.mdp_bin()
    store.opts.prefer_global_mdp = true
    vim.fn.executable = function(p)
      if p == in_tree then return 1 end
      return 0
    end
    assert(paths.resolve_mdp() == in_tree, "expected in-tree fallback when PATH mdp absent")
  end)

  it("falls back to PATH mdp when the in-tree binary is missing", function()
    vim.fn.executable = function(p)
      if p == "mdp" then return 1 end
      return 0
    end
    assert(paths.resolve_mdp() == "mdp", "expected PATH mdp fallback when in-tree absent")
  end)

  it("returns nil when neither binary is available", function()
    vim.fn.executable = function() return 0 end
    assert(paths.resolve_mdp() == nil, "expected nil when no mdp is reachable")
  end)
end)
