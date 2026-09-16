local M = {}

local watcher
local state

local function is_directory(path)
	return vim.fn.isdirectory(path) == 1
end

local function inside(root, path)
	return path == root or path:sub(1, #root + 1) == root .. "/"
end

local function resolve(root, path)
	if type(path) ~= "string" or path == "" then
		return nil, "agent path must be a non-empty string"
	end
	if path:sub(1, 1) == "/" or path:match("^%a:[/\\]") then
		return nil, "agent path must be repository-relative"
	end
	root = vim.fs.normalize(root)
	local absolute = vim.fs.normalize(vim.fs.joinpath(root, path))
	if not inside(root, absolute) then
		return nil, "agent path is outside the current repository"
	end
	local real_root = vim.uv.fs_realpath(root) or root
	local probe, real = absolute
	repeat
		real = vim.uv.fs_realpath(probe)
		probe = vim.fs.dirname(probe)
	until real or probe == vim.fs.dirname(probe)
	if real and not inside(real_root, real) then
		return nil, "agent path resolves outside the current repository"
	end
	return absolute, absolute:sub(#root + 2)
end

local function git(args, root)
	local command = { "git", "-C", root }
	vim.list_extend(command, args)
	return vim.system(command, { text = true }):wait()
end

function M.protect(root, path, enabled)
	local absolute, relative = resolve(root, path)
	if not absolute then
		return nil, relative
	end
	local ignored = git({ "check-ignore", "-q", "--no-index", "--", relative }, root)
	if ignored.code == 0 then
		return absolute
	end
	if enabled == false then
		return absolute, "agent response path is visible to Git: " .. relative
	end
	local result = git({ "rev-parse", "--git-path", "info/exclude" }, root)
	if result.code ~= 0 or vim.trim(result.stdout or "") == "" then
		return absolute, "could not locate repository-local Git exclude file; agent response path may be visible to Git"
	end
	local exclude = vim.trim(result.stdout)
	if exclude:sub(1, 1) ~= "/" then
		exclude = vim.fs.normalize(vim.fs.joinpath(root, exclude))
	end
	local pattern = relative:find("^%.quickfix%-review/") and "/.quickfix-review/" or "/" .. relative
	local lines = vim.fn.filereadable(exclude) == 1 and vim.fn.readfile(exclude) or {}
	if not vim.tbl_contains(lines, pattern) then
		local ok, write_err = pcall(vim.fn.writefile, { pattern }, exclude, "a")
		if not ok or write_err ~= 0 then
			return absolute, "could not protect agent response path in .git/info/exclude; path may be visible to Git"
		end
	end
	ignored = git({ "check-ignore", "-q", "--no-index", "--", relative }, root)
	if ignored.code ~= 0 then
		return absolute, "agent response path remains visible to Git: " .. relative
	end
	return absolute
end

local function close(handle)
	if handle and not handle:is_closing() then
		handle:stop()
		handle:close()
	end
end

function M.stop()
	close(watcher)
	watcher, state = nil, nil
end

local function payload_name(name)
	if name == state.basename then
		return true
	end
	return name:sub(-#state.basename - 1) == "-" .. state.basename
end

local function payloads(ready_only)
	local paths = {}
	if not is_directory(state.dir) then
		return paths
	end
	for name, kind in vim.fs.dir(state.dir) do
		if kind == "file" then
			local payload = ready_only and name:match("^(.*)%.ready$") or name
			if payload and payload_name(payload) then
				paths[#paths + 1] = vim.fs.joinpath(state.dir, payload)
			end
		end
	end
	table.sort(paths)
	return paths
end

local function read_once(path, ready)
	if ready and vim.fn.delete(ready) ~= 0 then
		if vim.fn.filereadable(ready) == 0 then
			return nil, nil, true
		end
		return nil, "could not claim ready agent response: " .. ready
	end
	local fd = io.open(path, "rb")
	if not fd then
		return nil, "findings file is not readable: " .. path
	end
	local contents = fd:read("*a")
	fd:close()
	local ok, payload = pcall(vim.json.decode, contents)
	if not ok then
		return nil, "invalid findings JSON: " .. tostring(payload)
	end
	local result, err = state.import(payload, "agent:" .. vim.fn.sha256(contents))
	if not result then
		return nil, err
	end
	if vim.fn.delete(path) ~= 0 then
		return nil, "response imported but could not be consumed: " .. path
	end
	return result
end

local function drain(ready_only, report)
	if not state then
		return nil, "findings watcher is not configured"
	end
	local found, last, first_err = false, nil, nil
	for _, path in ipairs(payloads(ready_only)) do
		found = true
		local ready = ready_only and path .. ".ready" or nil
		local result, err, skipped = read_once(path, ready)
		if result then
			last = result
			state.done(result)
		elseif not skipped then
			first_err = first_err or err
			if report then
				state.failed(err)
			end
		end
	end
	if first_err then
		return nil, first_err
	end
	if not found then
		return nil, "no agent response files found"
	end
	return last
end

function M.reload()
	return drain(false, false)
end

local function start_watcher(dir, callback)
	watcher = assert(vim.uv.new_fs_event())
	local ok, err = watcher:start(dir, {}, vim.schedule_wrap(callback))
	if not ok then
		close(watcher)
		watcher = nil
		return nil, "could not watch findings directory: " .. tostring(err)
	end
	return true
end

local function activate()
	if not state or not is_directory(state.dir) then
		return false
	end
	local protect_ok, protected, warning = pcall(M.protect, state.root, state.path, state.protect_git)
	if not protect_ok then
		warning = "could not protect agent response path; path may be visible to Git: " .. tostring(protected)
	end
	if warning then
		state.warn(warning)
	end
	close(watcher)
	watcher = nil
	state.watch_dir = state.dir
	local ok, err = start_watcher(state.dir, function(event_err, filename)
		if not state then
			return
		elseif event_err then
			state.failed(event_err)
		elseif not filename or filename:sub(-6) == ".ready" then
			drain(true, true)
		end
	end)
	if not ok then
		state.watch_dir = nil
		return nil, err
	end
	drain(true, true)
	return true
end

local await_directory

await_directory = function()
	if is_directory(state.dir) then
		return activate()
	end
	local parent = vim.fs.dirname(state.dir)
	while inside(state.root, parent) and not is_directory(parent) do
		local next_parent = vim.fs.dirname(parent)
		if next_parent == parent then
			break
		end
		parent = next_parent
	end
	if state.watch_dir == parent then
		return true
	end
	close(watcher)
	watcher = nil
	state.watch_dir = parent
	local ok, err = start_watcher(parent, function(event_err)
		if not state then
			return
		elseif event_err then
			state.failed(event_err)
		else
			local waiting, wait_err = await_directory()
			if not waiting and wait_err then
				state.failed(wait_err)
			end
		end
	end)
	if not ok then
		state.watch_dir = nil
		return nil, err
	end
	return true
end

function M.setup(opts)
	M.stop()
	local absolute, resolve_err = resolve(opts.root, opts.path)
	if not absolute then
		return nil, resolve_err
	end
	local dir = vim.fs.dirname(absolute)
	state = {
		root = vim.fs.normalize(opts.root),
		path = opts.path,
		dir = dir,
		basename = vim.fs.basename(absolute),
		protect_git = opts.protect_git,
		import = assert(opts.import),
		done = opts.done or function() end,
		failed = opts.failed or function() end,
		warn = opts.warn or function() end,
	}
	local ok, err = await_directory()
	if not ok then
		M.stop()
		return nil, err
	end
	return { path = absolute }
end

return M
