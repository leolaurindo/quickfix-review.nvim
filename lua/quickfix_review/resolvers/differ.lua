local M = { name = "differ", priority = 90, renderable = true }
local location = require("quickfix_review.location")

local function view_for(bufnr)
	local ok, differ = pcall(require, "differ.view")
	if not ok or type(differ.for_buf) ~= "function" then
		return nil
	end
	return differ.for_buf(bufnr)
end

function M.detect(bufnr)
	return vim.api.nvim_buf_get_name(bufnr):find("^differ://") ~= nil
end

local function column_for(view, bufnr)
	for _, column in ipairs(view and view.columns or {}) do
		if column.bufnr == bufnr then
			return column
		end
	end
end

function M.ignore_side(bufnr)
	local view = view_for(bufnr)
	local column = column_for(view, bufnr)
	return column and column.side == "unified" or false
end

local function map_lines(view, bufnr, lnum)
	local column = column_for(view, bufnr)
	local map = column and column.map
	if not map or not map.lines then
		return nil
	end
	local entry = map.lines[lnum]
	if not entry then
		return nil
	end
	return { old = entry.old, new = entry.new, side = entry.kind == "new" and "new" or entry.kind == "old" and "old" }
end

local function base_location(view, bufnr, winid)
	local column = column_for(view, bufnr)
	local mapped = map_lines(view, bufnr, vim.api.nvim_win_get_cursor(winid)[1])
	if not column or not mapped then
		return nil
	end
	local model = view.model
	local root = location.repo_root(model.root or vim.fn.getcwd()) or model.root or vim.fn.getcwd()
	local line, side = mapped.new, "new"
	if column.side == "old" or not line then
		line, side = mapped.old, "old"
	end
	return line and { root = root, file = model.path, line = line, side = side } or nil
end

function M.location(bufnr, winid)
	local view = view_for(bufnr)
	local loc = view and base_location(view, bufnr, winid)
	if not loc then
		return nil
	end
	local revision = loc.side == "old" and view.model.old_rev or view.model.new_rev
	if revision and revision:match("^%x%x%x%x%x%x%x+") then
		loc.revision, loc.hash = revision, revision
	end
	return loc
end

function M.range_location(bufnr, start_line, stop_line)
	local view = view_for(bufnr)
	if not view then
		return nil
	end
	local first, last = map_lines(view, bufnr, start_line), map_lines(view, bufnr, stop_line)
	if not first or not last then
		return nil
	end
	local column = column_for(view, bufnr)
	local line, side = first.new, "new"
	if not column or column.side == "old" or not line then
		line, side = first.old, "old"
	end
	local line_end = side == "old" and last.old or last.new
	if line and line_end and line_end < line then
		line, line_end = line_end, line
	end
	local model = view.model
	local root = location.repo_root(model.root or vim.fn.getcwd()) or model.root or vim.fn.getcwd()
	local loc = line and { root = root, file = model.path, line = line, line_end = line_end, side = side } or nil
	local revision = side == "old" and model.old_rev or model.new_rev
	if loc and revision and revision:match("^%x%x%x%x%x%x%x+") then
		loc.revision, loc.hash = revision, revision
	end
	return loc
end

local function display_line(map, source, side)
	return source and map["from_" .. side] and map["from_" .. side][source] or nil
end

function M.display_lines(value, bufnr)
	local view = view_for(bufnr)
	local column = column_for(view, bufnr)
	local map = column and column.map
	if not map then
		return {}
	end
	local side = value.side or "new"
	local first = display_line(map, value.line, side)
	local last = display_line(map, value.line_end or value.line, side)
	if first == last then
		return first and { first } or {}
	end
	local lines = {}
	if first then
		lines[#lines + 1] = first
	end
	if last then
		lines[#lines + 1] = last
	end
	return lines
end

return M
