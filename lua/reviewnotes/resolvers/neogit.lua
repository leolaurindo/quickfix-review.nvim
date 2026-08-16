local M = {}

M.name = "neogit"
M.priority = 70
M.renderable = false -- neogit re-renders its ui; inline marks get wiped

local store = require("reviewnotes.store")

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

-- ui:get_hunk_or_filename_under_cursor() returns { hunk=..., filename=... }.
-- The hunk carries `.file`, `.index_from`, `.disk_from`, `.lines`.
local function cursor_hunk(ui)
	if not ui or type(ui.get_hunk_or_filename_under_cursor) ~= "function" then
		return nil
	end
	local ok, hit = pcall(ui.get_hunk_or_filename_under_cursor, ui)
	if ok and hit then
		return hit
	end
end

---@return table|nil { root, file, line, line_end, side, revision, hash }
local function resolve_from_hunk(ui, root, oid)
	local hit = cursor_hunk(ui)
	if not hit then
		return nil
	end

	-- File-level note (cursor on a file row).
	if hit.filename then
		return {
			root = root,
			file = hit.filename,
			line = nil,
			line_end = nil,
			side = nil,
			revision = nil,
			hash = oid,
		}
	end

	-- Line note (cursor inside a hunk).
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
		return { root = root, file = file, line = nil, line_end = nil, side = "new", revision = nil, hash = oid }
	end

	-- Find the component that owns this hunk for its row_start, then translate.
	local comp
	if type(ui.get_component_under_cursor) == "function" then
		local okc, c = pcall(ui.get_component_under_cursor, ui, function(c)
			return c.options and c.options.hunk == hunk
		end)
		comp = okc and c or nil
	end

	local lnum = vim.api.nvim_win_get_cursor(0)[1]
	local offset = comp and comp.position and (lnum - comp.position.row_start) or 1
	local loc = jump.translate_hunk_location(hunk, offset)
	if not loc then
		-- Cursor may be on the hunk header / outside translated range: anchor at
		-- the hunk's new-start line.
		return {
			root = root,
			file = file,
			line = hunk.index_from,
			line_end = nil,
			side = "new",
			revision = nil,
			hash = oid,
		}
	end
	local line, side = loc.new, "new"
	if not line then
		line, side = loc.old, "old"
	end
	return { root = root, file = file, line = line, line_end = nil, side = side, revision = nil, hash = oid }
end

function M.location(bufnr, _winid)
	local ft = vim.bo[bufnr].filetype
	local root = store.repo_root() or vim.fn.getcwd()
	root = store.repo_root(root) or root

	if ft == "NeogitStatus" then
		local inst = status_instance()
		if not inst or inst.buffer.handle ~= bufnr then
			return nil
		end
		return resolve_from_hunk(inst.buffer.ui, root, nil)
	end

	if ft == "NeogitCommitView" then
		local inst = commit_view_instance()
		if not inst or inst.buffer.handle ~= bufnr then
			return nil
		end
		local oid = inst.commit_info and inst.commit_info.oid
		return resolve_from_hunk(inst.buffer.ui, root, oid)
	end

	return nil
end

return M
