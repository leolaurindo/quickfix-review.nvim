local M = { name = "normal", priority = 0, renderable = true }
local location = require("quickfix_notes.location")

function M.detect(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= "" and not name:match("^%w+://")
end

local function resolve(bufnr, winid)
	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" then
		return nil
	end
	local root = location.repo_root(file)
	return {
		root = root,
		path = location.relative(root, file),
		line = vim.api.nvim_win_get_cursor(winid)[1],
	}
end

function M.location(bufnr, winid)
	return resolve(bufnr, winid)
end

function M.range_location(bufnr, start_line, stop_line)
	local value = resolve(bufnr, vim.api.nvim_get_current_win())
	if value then
		value.line, value.line_end = start_line, stop_line
	end
	return value
end

function M.anchor(note)
	return note.line_end or note.line
end

return M
