local store = require("md-preview.state")

local M = {}

function M.register(plugin)
  if store.state.augroup then
    pcall(vim.api.nvim_del_augroup_by_id, store.state.augroup)
  end
  local aug = vim.api.nvim_create_augroup("MdPreview", { clear = true })
  store.state.augroup = aug

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = aug,
    pattern = "*.md",
    callback = function() plugin.on_save() end,
  })

  vim.api.nvim_create_autocmd("CursorMoved", {
    group = aug,
    pattern = "*.md",
    callback = function() plugin.on_cursor_moved() end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    group = aug,
    pattern = "*.md",
    callback = function()
      local f = vim.fn.expand("<afile>:p")
      if f == store.state.file then plugin.close() end
    end,
  })

  vim.api.nvim_create_autocmd("VimLeavePre", {
    group = aug,
    callback = function() plugin.close() end,
  })
end

return M
