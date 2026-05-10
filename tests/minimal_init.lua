local cache = vim.fn.stdpath("cache") .. "/md-preview-tests"
local plenary = cache .. "/plenary.nvim"

if vim.fn.isdirectory(plenary) == 0 then
  vim.fn.mkdir(cache, "p")
  vim.fn.system({
    "git",
    "clone",
    "--depth",
    "1",
    "https://github.com/nvim-lua/plenary.nvim.git",
    plenary,
  })
end

vim.opt.rtp:prepend(plenary)

local here = debug.getinfo(1, "S").source:sub(2)
local repo = vim.fn.fnamemodify(here, ":h:h")
vim.opt.rtp:prepend(repo)

vim.cmd("runtime plugin/plenary.vim")
