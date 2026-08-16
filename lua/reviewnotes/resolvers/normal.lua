local M = {}

M.name = "normal"
M.priority = 0
M.renderable = true

function M.detect(bufnr, _winid)
	local name = vim.api.nvim_buf_get_name(bufnr)
	return name ~= "" and name:find("^%w+://") == nil
end

local function normalize(bufnr, winid)
	local file = vim.api.nvim_buf_get_name(bufnr)
	if file == "" then
		return nil
	end
	local store = require("reviewnotes.store")
	local root = store.repo_root(file) or vim.fn.getcwd()
	local rel = file:find(root .. "/", 1, true) == 1 and file:sub(#root + 2) or file
	return {
		root = root,
		file = rel,
		line = vim.api.nvim_win_get_cursor(winid)[1],
		line_end = nil,
		side = nil,
		revision = nil,
		hash = nil,
	}
end

function M.location(bufnr, winid)
	return normalize(bufnr, winid)
end

function M.range_location(bufnr, start_line, stop_line)
	local loc = normalize(bufnr, vim.api.nvim_get_current_win())
	if not loc then
		return nil
	end
	loc.line = start_line
	loc.line_end = stop_line
	return loc
end

function M.anchor(note, _bufnr)
	-- Note lines refer to the file; normal buffers hold the file directly.
	-- Ranges anchor at the bottom of the selection.
	if note.line_end and note.line_end ~= note.line then
		return note.line_end
	end
	return note.line
end

return M
