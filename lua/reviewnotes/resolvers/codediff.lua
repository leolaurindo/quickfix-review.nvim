local M = {}

M.name = "codediff"
M.priority = 100
M.renderable = true

local store = require("reviewnotes.store")

local function lifecycle()
	local ok, mod = pcall(require, "codediff.ui.lifecycle")
	if ok and type(mod) == "table" then
		return mod
	end
end

local function relpath(path, root)
	if not path or path == "" then
		return nil
	end
	if root and path:find(root .. "/", 1, true) == 1 then
		return path:sub(#root + 2)
	end
	return path
end

local function tab_for(bufnr)
	local lc = lifecycle()
	if not lc then
		return nil
	end
	local ok, tab = pcall(lc.find_tabpage_by_buffer, bufnr)
	if ok and tab then
		return tab
	end
	return vim.api.nvim_get_current_tabpage()
end

function M.detect(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	if name:find("^codediff://") then
		return true
	end
	local lc = lifecycle()
	if not lc then
		return false
	end
	local tab = tab_for(bufnr)
	local ok, ob, mb = pcall(lc.get_buffers, tab)
	if not ok then
		return false
	end
	return bufnr == ob or bufnr == mb
end

function M.location(bufnr, winid)
	local lc = lifecycle()
	if not lc then
		return nil
	end
	local tab = tab_for(bufnr)
	local ok, ob, mb = pcall(lc.get_buffers, tab)
	if not ok or not ob or not mb then
		return nil
	end
	if bufnr ~= ob and bufnr ~= mb then
		return nil
	end

	local okp, op, mp = pcall(lc.get_paths, tab)
	if not okp then
		return nil
	end
	local okg, ctx = pcall(lc.get_git_context, tab)
	ctx = okg and ctx or {}
	local root = ctx.git_root or store.repo_root(vim.api.nvim_buf_get_name(bufnr)) or vim.fn.getcwd()
	root = store.repo_root(root) or root

	local is_original = bufnr == ob
	local file = relpath(is_original and op or mp, root)
	if not file then
		return nil
	end

	return {
		root = root,
		file = file,
		line = vim.api.nvim_win_get_cursor(winid)[1],
		line_end = nil,
		side = is_original and "old" or "new",
		revision = (is_original and ctx.original_revision or ctx.modified_revision) or nil,
		hash = nil,
	}
end

-- codediff renders into real-file-content buffers: old side on the left,
-- new side on the right. Note line numbers map 1:1 to the buffer.
function M.anchor(note, _bufnr)
	return note.line
end

-- Re-render marks when codediff swaps files / opens.
function M.on_attach(callback)
	local group = vim.api.nvim_create_augroup("reviewnotes_codediff", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
		callback = callback,
	})
end

return M
