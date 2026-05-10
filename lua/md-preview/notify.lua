local M = {}

local function emit(level, msg) vim.notify("[md-preview] " .. msg, level) end

function M.log(msg) emit(vim.log.levels.DEBUG, msg) end
function M.info(msg) emit(vim.log.levels.INFO, msg) end
function M.warn(msg) emit(vim.log.levels.WARN, msg) end
function M.err(msg) emit(vim.log.levels.ERROR, msg) end

return M
