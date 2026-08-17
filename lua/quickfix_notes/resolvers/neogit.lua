local M = {}

M.name = "neogit"
M.priority = 70
M.renderable = false

local location = require("quickfix_notes.location")

local function status_instance()
	local ok, status = pcall(require, "neogit.buffers.status")
	if not ok or not status.instance then
		return nil
	end
	local inst = status.instance(vim.uv.cwd())
	return inst and inst.buffer and inst.buffer.handle and inst or nil
end

local function commit_view_instance()
	local ok, cv = pcall(require, "neogit.buffers.commit_view")
	if not ok or not cv.instance then
		return nil
	end
	local inst = cv.instance
	return inst and inst.buffer and inst.buffer.handle and inst or nil
end

function M.detect(bufnr)
	local ft = vim.bo[bufnr].filetype
	if ft == "NeogitStatus" then
		local inst = status_instance()
		return inst and inst.buffer.handle == bufnr
	end
	if ft == "NeogitCommitView" then
		local inst = commit_view_instance()
		return inst and inst.buffer.handle == bufnr
	end
	return false
end

local function cursor_hunk(ui)
	if not ui or type(ui.get_hunk_or_filename_under_cursor) ~= "function" then
		return nil
	end
	local ok, hit = pcall(ui.get_hunk_or_filename_under_cursor, ui)
	return ok and hit or nil
end

local function resolve_from_hunk(ui, root, oid)
	local hit = cursor_hunk(ui)
	if not hit then
		return nil
	end
	if hit.filename then
		return { root = root, file = hit.filename, hash = oid }
	end
	local hunk = hit.hunk
	if not hunk or not hunk.file then
		return nil
	end
	local file = vim.trim(hunk.file)
	if file == "" then
		return nil
	end
	local ok_jump, jump = pcall(require, "neogit.lib.jump")
	if not ok_jump or type(jump.translate_hunk_location) ~= "function" then
		return { root = root, file = file, side = "new", hash = oid }
	end
	local comp
	if type(ui.get_component_under_cursor) == "function" then
		local okc, value = pcall(ui.get_component_under_cursor, ui, function(component)
			return component.options and component.options.hunk == hunk
		end)
		comp = okc and value or nil
	end
	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local offset = comp and comp.position and (lnum - comp.position.row_start) or 1
	local loc = jump.translate_hunk_location(hunk, offset)
	if not loc then
		return { root = root, file = file, line = hunk.index_from, side = "new", hash = oid }
	end
	local line, side = loc.new, "new"
	if not line then
		line, side = loc.old, "old"
	end
	return { root = root, file = file, line = line, side = side, hash = oid }
end

function M.location(bufnr)
	local ft = vim.bo[bufnr].filetype
	local root = location.repo_root() or vim.fn.getcwd()
	root = location.repo_root(root) or root
	if ft == "NeogitStatus" then
		local inst = status_instance()
		return inst and inst.buffer.handle == bufnr and resolve_from_hunk(inst.buffer.ui, root, nil)
	end
	if ft == "NeogitCommitView" then
		local inst = commit_view_instance()
		local oid = inst and inst.commit_info and inst.commit_info.oid
		return inst and inst.buffer.handle == bufnr and resolve_from_hunk(inst.buffer.ui, root, oid)
	end
end

return M
