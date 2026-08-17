local M = {}

-- Store is scoped to a repo + branch (or repo + short-hash when detached).
-- Notes survive across sessions and are cleared only via export-and-clear or
-- an explicit clear command.

local notes = {} -- list of note records
local scope = nil -- { root, branch }

-- --- helpers ---------------------------------------------------------------

local function shell(args)
	local out = vim.fn.system(args)
	if vim.v.shell_error ~= 0 then
		return nil
	end
	return vim.trim(out)
end

local function git_dir(path)
	if path and vim.fn.filereadable(path) == 1 then
		return vim.fn.fnamemodify(path, ":p:h")
	end
	return path or vim.fn.getcwd()
end

function M.repo_root(path)
	return shell({ "git", "-C", git_dir(path), "rev-parse", "--show-toplevel" })
end

local function current_branch(root)
	if not root then
		return nil
	end
	local branch = shell({ "git", "-C", root, "branch", "--show-current" })
	if branch and branch ~= "" then
		return branch
	end
	return shell({ "git", "-C", root, "rev-parse", "--short", "HEAD" })
end

local function safe_id(v)
	return (v or "detached"):gsub("^/", ""):gsub("[/:\\]", "_")
end

local function scope_id(root, branch)
	return safe_id(root) .. "-" .. safe_id(branch)
end

local function data_dir()
	return vim.fn.stdpath("data") .. "/quickfix-notes"
end

local function legacy_data_dir()
	return vim.fn.stdpath("data") .. "/reviewnotes"
end

local function file_for(root, branch, directory)
	return (directory or data_dir()) .. "/" .. scope_id(root, branch) .. ".json"
end

-- --- persistence ------------------------------------------------------------

---Reload notes for the current repo+branch. Returns true if scope changed.
function M.switch_scope(root, branch)
	root = root or M.repo_root()
	branch = branch or current_branch(root)
	if not root then
		scope = nil
		notes = {}
		return true
	end

	if scope and scope.root == root and scope.branch == branch then
		return false
	end
	scope = { root = root, branch = branch }

	notes = {}
	local file = file_for(root, branch)
	if vim.fn.filereadable(file) == 0 then
		file = file_for(root, branch, legacy_data_dir())
	end
	if vim.fn.filereadable(file) == 1 then
		local ok, data = pcall(vim.fn.json_decode, table.concat(vim.fn.readfile(file), "\n"))
		if ok and type(data) == "table" then
			notes = data
		end
	end
	return true
end

function M.scope()
	return scope and vim.deepcopy(scope) or nil
end

local function persist()
	if not scope then
		return
	end
	vim.fn.mkdir(data_dir(), "p")
	vim.fn.writefile({ vim.fn.json_encode(notes) }, file_for(scope.root, scope.branch))
end

-- --- in-memory ops ---------------------------------------------------------

local function new_id()
	return table.concat({ os.time(), vim.fn.reltimefloat(vim.fn.reltime()), math.random(1000000) }, "-")
end

function M.add(loc, text)
	local note = {
		id = new_id(),
		created_at = os.time(),
		file = loc.file,
		line = loc.line,
		line_end = loc.line_end,
		side = loc.side,
		revision = loc.revision,
		hash = loc.hash,
		list_key = loc.list_key,
		item_key = loc.item_key,
		text = text,
	}
	notes[#notes + 1] = note
	persist()
	return note
end

function M.update(id, fields)
	for _, n in ipairs(notes) do
		if n.id == id then
			for k, v in pairs(fields) do
				n[k] = v
			end
			persist()
			return n
		end
	end
end

function M.get(id)
	for _, n in ipairs(notes) do
		if n.id == id then
			return n
		end
	end
end

function M.delete(id)
	for i, n in ipairs(notes) do
		if n.id == id then
			table.remove(notes, i)
			persist()
			return true
		end
	end
end

function M.clear()
	local count = #notes
	notes = {}
	persist()
	return count
end

function M.all()
	return notes
end

---Notes for a specific file in the current scope.
function M.for_file(file)
	return vim.tbl_filter(function(n)
		return n.file == file
	end, notes)
end

---The note attached to the same (file, line, side, hash) as `loc`.
function M.at(loc)
	if loc.item_key then
		for _, n in ipairs(notes) do
			if n.item_key == loc.item_key then
				return n
			end
		end
		return
	end
	for _, n in ipairs(notes) do
		if n.file == loc.file and n.line == loc.line and n.side == loc.side and n.hash == loc.hash then
			return n
		end
	end
end

function M.count()
	return #notes
end

return M
