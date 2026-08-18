local M = { name = "generic", priority = -10, renderable = false }
local location = require("quickreview.location")

local function file_path(bufnr)
	local name = vim.api.nvim_buf_get_name(bufnr)
	local path = name:match("^[%w][%w+.-]*://(.+)$")
	if not path then
		return nil
	end
	path = vim.uri_decode(path)
	if not path:match("^/") and not path:match("^%a:[/\\]") then
		return nil
	end
	return vim.fs.normalize(path)
end

function M.detect(bufnr)
	local path = file_path(bufnr)
	return path and vim.fn.filereadable(path) == 1 or false
end

function M.location(bufnr)
	local path = file_path(bufnr)
	if not path or vim.fn.filereadable(path) ~= 1 then
		return nil
	end
	local root = location.repo_root(path)
	return {
		root = root,
		path = location.relative(root, path),
	}
end

return M
