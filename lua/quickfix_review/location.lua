local M = {}

local function normalize(path)
	return path and vim.fs.normalize(path) or nil
end

local function absolute(root, path)
	if not path or path == "" then
		return nil
	end
	if path:match("^%a:[/\\]") or path:sub(1, 1) == "/" then
		return normalize(path)
	end
	return normalize(vim.fs.joinpath(root or vim.fn.getcwd(), path))
end

function M.repo_root(path)
	path = path or vim.fn.getcwd()
	if vim.fn.filereadable(path) == 1 then
		path = vim.fn.fnamemodify(path, ":p:h")
	end
	local result = vim.fn.system({ "git", "-C", path, "rev-parse", "--show-toplevel" })
	if vim.v.shell_error == 0 and vim.trim(result) ~= "" then
		return normalize(vim.trim(result))
	end
	return normalize(path)
end

function M.relative(root, path)
	root, path = normalize(root), normalize(path)
	if not path then
		return nil
	end
	if root and (path == root or path:find(root .. "/", 1, true) == 1) then
		return path == root and "" or path:sub(#root + 2)
	end
	return path
end

function M.canonical(loc)
	if type(loc) ~= "table" then
		return nil
	end
	local root = normalize(loc.root or vim.fn.getcwd())
	local path = M.relative(root, absolute(root, loc.path or loc.file))
	local line = tonumber(loc.line)
	local line_end = tonumber(loc.line_end)
	if line and line <= 0 then
		line = nil
	end
	if not line or not line_end or line_end <= line then
		line_end = nil
	end
	return {
		root = root,
		path = path,
		line = line,
		line_end = line_end,
		side = loc.side,
		revision = loc.revision,
		hash = loc.hash,
		resolver = loc.resolver,
		fingerprint = vim.deepcopy(loc.fingerprint),
		deletion = loc.deletion,
	}
end

function M.absolute(loc)
	local value = M.canonical(loc)
	return value and absolute(value.root, value.path)
end

function M.equal(a, b)
	a, b = M.canonical(a), M.canonical(b)
	if not a or not b then
		return false
	end
	return a.root == b.root
		and a.path == b.path
		and a.line == b.line
		and a.line_end == b.line_end
		and a.side == b.side
		and a.revision == b.revision
		and a.hash == b.hash
end

function M.key(loc)
	local value = M.canonical(loc)
	if not value then
		return nil
	end
	return table.concat({
		value.root or "",
		value.path or "",
		value.line or "",
		value.line_end or "",
		value.side or "",
		value.revision or "",
		value.hash or "",
	}, "\0")
end

return M
