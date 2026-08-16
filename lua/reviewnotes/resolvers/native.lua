local M = {}

M.name = "native"
M.priority = 10
M.renderable = true

-- Native `:diffthis` / `vim.wo.diff` windows over real files.
function M.detect(bufnr, winid)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= "" and vim.wo[winid].diff == true
end

function M.location(bufnr, winid)
	local normal = require("reviewnotes.resolvers.normal")
	return normal.location(bufnr, winid)
end

function M.range_location(bufnr, start_line, stop_line)
	local normal = require("reviewnotes.resolvers.normal")
	return normal.range_location(bufnr, start_line, stop_line)
end

function M.anchor(note, _bufnr)
	return note.line
end

return M
