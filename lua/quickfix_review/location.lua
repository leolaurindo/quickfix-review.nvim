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

-- `repo_root` used to run a synchronous `git rev-parse --show-toplevel` on every call,
-- and it sits on the hover path (hover_payload -> resolver.location -> normal.resolve),
-- i.e. a git process per cursor move and per hover. That blocking call was the last
-- thing making the note hover visibly flicker the cursor: it is cheap and invisible when
-- it happens inside a cursor gesture (float.permanent / delay 0), but on the deferred
-- hover it fires on an otherwise idle screen. The result only depends on the filesystem,
-- so resolve it once per path and drop the cache when the working directory changes.
local repo_root_cache = {}

function M.repo_root(path)
	path = path or vim.fn.getcwd()
	if vim.fn.filereadable(path) == 1 then
		path = vim.fn.fnamemodify(path, ":p:h")
	end
	local cached = repo_root_cache[path]
	if cached then
		return cached
	end
	local root
	local result = vim.fn.system({ "git", "-C", path, "rev-parse", "--show-toplevel" })
	if vim.v.shell_error == 0 and vim.trim(result) ~= "" then
		root = normalize(vim.trim(result))
	else
		root = normalize(path)
	end
	repo_root_cache[path] = root
	return root
end

function M.clear_cache()
	repo_root_cache = {}
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
