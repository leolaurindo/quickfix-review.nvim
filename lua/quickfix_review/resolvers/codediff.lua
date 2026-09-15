local M = { name = "codediff", priority = 100, renderable = true }
local location = require("quickfix_review.location")

local function lifecycle()
	local ok, mod = pcall(require, "codediff.ui.lifecycle")
	return ok and type(mod) == "table" and mod or nil
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
	return ok and tab or vim.api.nvim_get_current_tabpage()
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
	local ok, ob, mb = pcall(lc.get_buffers, tab_for(bufnr))
	return ok and (bufnr == ob or bufnr == mb) or false
end

function M.location(bufnr, winid)
	local lc = lifecycle()
	if not lc then
		return nil
	end
	local tab = tab_for(bufnr)
	local ok, ob, mb = pcall(lc.get_buffers, tab)
	if not ok or not ob or not mb or (bufnr ~= ob and bufnr ~= mb) then
		return nil
	end
	local okp, op, mp = pcall(lc.get_paths, tab)
	if not okp then
		return nil
	end
	local okg, ctx = pcall(lc.get_git_context, tab)
	ctx = okg and ctx or {}
	local root = ctx.git_root or location.repo_root(vim.api.nvim_buf_get_name(bufnr)) or vim.fn.getcwd()
	root = location.repo_root(root) or root
	local is_original = bufnr == ob
	local file = relpath(is_original and op or mp, root)
	if not file then
		return nil
	end
	return {
		root = root,
		file = file,
		line = vim.api.nvim_win_get_cursor(winid)[1],
		side = is_original and "old" or "new",
		revision = (is_original and ctx.original_revision or ctx.modified_revision) or nil,
	}
end

function M.anchor(note)
	return note.line_end or note.line
end

function M.on_attach(callback)
	local group = vim.api.nvim_create_augroup("quickfix_review_codediff", { clear = true })
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = { "CodeDiffOpen", "CodeDiffFileSelect" },
		callback = callback,
	})
end

return M
