describe("navigate.parse", function()
  local navigate = require("md-preview.navigate")

  it("returns the path for a valid navigate line", function()
    assert.equals("/tmp/foo/bar.md", navigate.parse("[md-preview] navigate: /tmp/foo/bar.md"))
  end)

  it("returns nil for the serving banner", function()
    assert.is_nil(navigate.parse("[md-preview] Serving on http://localhost:9753/"))
  end)

  it("returns nil for unrelated log lines", function()
    assert.is_nil(navigate.parse("anything else"))
    assert.is_nil(navigate.parse(""))
  end)

  it("returns nil for non-string inputs", function()
    assert.is_nil(navigate.parse(nil))
    assert.is_nil(navigate.parse(42))
  end)
end)

describe("navigate.follow", function()
  local fresh = function()
    package.loaded["md-preview"] = nil
    package.loaded["md-preview.state"] = nil
    package.loaded["md-preview.navigate"] = nil
    package.loaded["md-preview.notify"] = nil
    return require("md-preview.navigate"), require("md-preview.state")
  end

  it("updates state.file even when no editor window holds the current file", function()
    local navigate, store = fresh()
    store.state.file = "/tmp/never-open.md"
    navigate.follow("/tmp/elsewhere.md")
    assert.equals("/tmp/elsewhere.md", store.state.file)
  end)

  it("is a no-op when the new file matches state.file", function()
    local navigate, store = fresh()
    store.state.file = "/tmp/same.md"
    -- If follow tried to :edit, the path would be invalid and throw — the
    -- early-return is what keeps this safe.
    navigate.follow("/tmp/same.md")
    assert.equals("/tmp/same.md", store.state.file)
  end)

  it("ignores empty new_file", function()
    local navigate, store = fresh()
    store.state.file = "/tmp/keep.md"
    navigate.follow("")
    assert.equals("/tmp/keep.md", store.state.file)
  end)

  it(":edits the new file in the window holding the current one", function()
    local navigate, store = fresh()
    local dir = vim.fn.tempname()
    vim.fn.mkdir(dir, "p")
    local a = dir .. "/a.md"
    local b = dir .. "/b.md"
    vim.fn.writefile({ "# a" }, a)
    vim.fn.writefile({ "# b" }, b)

    local saved_swap = vim.o.swapfile
    vim.o.swapfile = false
    vim.cmd("edit " .. vim.fn.fnameescape(a))
    store.state.file = vim.fn.fnamemodify(a, ":p")
    local win_with_a = vim.api.nvim_get_current_win()

    navigate.follow(vim.fn.fnamemodify(b, ":p"))

    assert.equals(vim.fn.fnamemodify(b, ":p"), store.state.file)
    local loaded = vim.api.nvim_buf_get_name(vim.api.nvim_win_get_buf(win_with_a))
    assert.equals(vim.fn.fnamemodify(b, ":p"), loaded)

    vim.cmd("silent! %bwipeout!")
    vim.o.swapfile = saved_swap
  end)
end)
