local M = {}

M.name = "diffs"
M.priority = 80
M.renderable = false

local location = require("quickfix_notes.location")

local function buf_var(bufnr, name)
	local ok, v = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	if ok then
		return v
	end
end

local function source(bufnr)
	local v = buf_var(bufnr, "diffs_source")
	if type(v) == "table" then
		return v
	end
end

-- diffs://<label>:<path>  or  diffs://split:left:endpoint:path
local function parse_name(name)
	local path = name:match("^diffs://[^:]+:(.+)$")
	if not path then
		return nil
	end
	path = path:gsub("%s*->%s*.*$", "")
	if path ~= "" then
		return path
	end
end

local function parse_split(name)
	local side, path = name:match("^diffs://split:([^:]+):[^:]+:(.+)$")
	if side and path then
		return { side = side, path = path }
	end
	return nil
end

function M.detect(bufnr)
	return vim.api.nvim_buf_get_name(bufnr):find("^diffs://") ~= nil
end

function M.location(bufnr, winid)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local src = source(bufnr)
	local root = (src and src.repo_root) or location.repo_root() or vim.fn.getcwd()
	root = location.repo_root(root) or root
	local branch = vim.fn.system({ "git", "-C", root, "branch", "--show-current" }):gsub("%s+$", "")

	local file, side
	if src and src.kind == "split_endpoint" then
		side = (src.side or buf_var(bufnr, "diffs_split_side")) == "left" and "old" or "new"
		file = src.path
	else
		local sp = parse_split(name)
		if sp then
			side = sp.side == "left" and "old" or "new"
			file = sp.path
		else
			file = (src and (src.path or src.old_path or src.working_path)) or parse_name(name)
			side = "new"
		end
	end
	if not file then
		return nil
	end

	return {
		root = root,
		file = file,
		line = vim.api.nvim_win_get_cursor(winid)[1],
		line_end = nil,
		side = side,
		revision = nil,
		hash = nil,
		branch = branch,
	}
end

return M
