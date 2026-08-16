local M = {}

M.name = "differ"
M.priority = 90
M.renderable = false -- differ re-renders its buffers; inline marks get wiped

local store = require("reviewnotes.store")

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

-- Map a buffer lnum to { old, new } via the view's LineMap, or nil.
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
	local side = entry.kind == "new" and "new" or entry.kind == "old" and "old" or nil
	return { old = entry.old, new = entry.new, side = side }
end

local function base_location(view, winid)
	local lnum = vim.api.nvim_win_get_cursor(winid)[1]
	local mapped = map_lines(view, lnum)
	if not mapped then
		return nil
	end

	local model = view.model
	local root = model.root or store.repo_root() or vim.fn.getcwd()
	root = store.repo_root(root) or root

	-- Prefer the "new" side line (matches the working tree / target commit).
	local line, side = mapped.new, "new"
	if not line then
		line, side = mapped.old, "old"
	end
	if not line then
		return nil
	end

	return {
		root = root,
		file = model.path,
		line = line,
		line_end = nil,
		side = side,
		revision = nil,
		hash = nil,
	}
end

function M.location(bufnr, winid)
	local view = view_for(bufnr)
	if not view then
		return nil
	end
	local loc = base_location(view, winid)
	if not loc then
		return nil
	end
	-- differ log diffs carry the target commit as new_rev.
	if view.model and view.model.new_rev and view.model.new_rev:match("^%x%x%x%x%x%x%x+") then
		loc.revision = view.model.new_rev
		loc.hash = view.model.new_rev
	end
	return loc
end

function M.range_location(bufnr, start_line, stop_line)
	local view = view_for(bufnr)
	if not view then
		return nil
	end
	local s = map_lines(view, start_line)
	local e = map_lines(view, stop_line)
	if not s or not e then
		return nil
	end
	local line, side = s.new or s.old, "new"
	if not line then
		line, side = s.old, "old"
	end
	local line_end = e.new or e.old
	if line and line_end and line_end < line then
		line, line_end = line_end, line
	end
	if not line then
		return nil
	end
	local model = view.model
	local root = model.root or store.repo_root() or vim.fn.getcwd()
	root = store.repo_root(root) or root
	local loc = {
		root = root,
		file = model.path,
		line = line,
		line_end = line_end,
		side = side,
		revision = nil,
		hash = nil,
	}
	if model.new_rev and model.new_rev:match("^%x%x%x%x%x%x%x+") then
		loc.revision = model.new_rev
		loc.hash = model.new_rev
	end
	return loc
end

return M
