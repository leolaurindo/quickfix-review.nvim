local M = { name = "diffs", priority = 80, renderable = false }
local location = require("quickfix_notes.location")

local function buf_var(bufnr, name)
	local ok, value = pcall(vim.api.nvim_buf_get_var, bufnr, name)
	return ok and value or nil
end

local function source(bufnr)
	local value = buf_var(bufnr, "diffs_source")
	return type(value) == "table" and value or nil
end

local function parse_name(name)
	local path = name:match("^diffs://[^:]+:(.+)$")
	path = path and path:gsub("%s*%-%>%s*.*$", "")
	return path ~= "" and path or nil
end

local function parse_split(name)
	local side, path = name:match("^diffs://split:([^:]+):[^:]+:(.+)$")
	return side and path and { side = side, path = path } or nil
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
		local split = parse_split(name)
		if split then
			side, file = split.side == "left" and "old" or "new", split.path
		else
			file, side = (src and (src.path or src.old_path or src.working_path)) or parse_name(name), "new"
		end
	end
	return file
			and {
				root = root,
				file = file,
				line = vim.api.nvim_win_get_cursor(winid)[1],
				side = side,
				branch = branch,
			}
		or nil
end

return M
