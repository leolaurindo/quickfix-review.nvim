local M = { name = "differ", priority = 90, renderable = false }
local location = require("quickreview.location")

local function view_for(bufnr)
	local ok, differ = pcall(require, "differ.view")
	if not ok then
		return nil
	end
	return differ.for_buf and differ.for_buf(bufnr) or differ.current()
end

function M.detect(bufnr)
	return vim.api.nvim_buf_get_name(bufnr):find("^differ://") ~= nil
end

local function map_lines(view, lnum)
	if not view then
		return nil
	end
	local map = view:map_for("unified") or view:map_for("new") or view:map_for("old")
	if not map or not map.lines then
		return nil
	end
	local entry = map.lines[lnum]
	if not entry then
		return nil
	end
	return { old = entry.old, new = entry.new, side = entry.kind == "new" and "new" or entry.kind == "old" and "old" }
end

local function base_location(view, winid)
	local mapped = map_lines(view, vim.api.nvim_win_get_cursor(winid)[1])
	if not mapped then
		return nil
	end
	local model = view.model
	local root = location.repo_root(model.root or vim.fn.getcwd()) or model.root or vim.fn.getcwd()
	local line, side = mapped.new, "new"
	if not line then
		line, side = mapped.old, "old"
	end
	return line and { root = root, file = model.path, line = line, side = side } or nil
end

function M.location(bufnr, winid)
	local view = view_for(bufnr)
	local loc = view and base_location(view, winid)
	if not loc then
		return nil
	end
	local revision = view.model.new_rev
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
	local first, last = map_lines(view, start_line), map_lines(view, stop_line)
	if not first or not last then
		return nil
	end
	local line, side = first.new, "new"
	if not line then
		line, side = first.old, "old"
	end
	local line_end = last.new or last.old
	if line and line_end and line_end < line then
		line, line_end = line_end, line
	end
	local model = view.model
	local root = location.repo_root(model.root or vim.fn.getcwd()) or model.root or vim.fn.getcwd()
	local loc = line and { root = root, file = model.path, line = line, line_end = line_end, side = side } or nil
	local revision = model.new_rev
	if loc and revision and revision:match("^%x%x%x%x%x%x%x+") then
		loc.revision, loc.hash = revision, revision
	end
	return loc
end

return M
